# Spec-06: Vector Store

**Status:** `[ ] not started`
**Phase:** Wave 2 — Knowledge Layer
**Default depends on (pgvector):** `vpc`, `rds`, `iam`

**Backend dependency map:**
| Backend | Requires |
|---------|----------|
| `pgvector` (default) | `vpc`, `rds`, `iam` |
| `opensearch-serverless` | `vpc`, `iam` |
| `bedrock-kb` | `spec-01-bedrock`, `spec-05-ai-storage`, `iam` |
**Blocks:** RAG pipeline in any AI framework
**Repo(s):** core-tfe-bootstrap-workspace-management

---

## Business Rule

The platform's knowledge retrieval interface must be backend-agnostic so that clients can
scale from relational to dedicated vector infrastructure without changing AI framework code.

---

## Goal

Provision vector storage for RAG (Retrieval-Augmented Generation) workloads. Supports three
backends — selected per client via config. Clients may run pgvector and OpenSearch simultaneously
for different query patterns. All backends expose the same Terraform outputs so AI frameworks
connect identically regardless of backend.

---

## Context

RAG enables AI agents to answer questions from a client's knowledge base without fine-tuning.
Documents are chunked → embedded → stored in a vector database → retrieved at query time.

### Dual-Backend Model

pgvector and OpenSearch Serverless serve different query patterns and may be deployed
simultaneously for clients that need both:

| Backend | Best for | Run with pgvector? | Cost |
|---------|----------|-------------------|------|
| `pgvector` | Filtered relational+vector ("Find invoices from Company X about server maintenance") | — | +$0 (reuses RDS) |
| `opensearch-serverless` | Unstructured memory, broad KB lookups, high-concurrency writes | Yes, alongside pgvector | ~$700/month |
| `bedrock-kb` | Fully managed ingestion for non-technical clients | No (replaces pgvector) | $0.10-0.30/document |

**Start with `pgvector` alone.** Add OpenSearch when you need broad unstructured KB search
at scale or concurrent agent writes exceed Aurora connection limits. Bedrock KB is a
third path — fully managed, but lower control.

```
pgvector alone (MVP)
  → pgvector + opensearch-serverless (scale: both active simultaneously)
  → bedrock-kb (fully managed, replaces both for non-technical clients)
```

### Tenant Index Isolation

Cross-tenant data contamination must be structurally impossible, not just IAM-controlled:

- **pgvector**: Each tenant uses a separate schema (`vectors_<tenant_id>`) or a `tenant_id` column
  enforced via Row Level Security (RLS). The default schema uses a `tenant_id` column with
  an RLS policy so a connection authenticated as tenant A cannot read tenant B's rows.
- **OpenSearch Serverless**: Each tenant uses a separate index
  (`<client_id>-<env>-<tenant_id>-knowledge`). Cross-tenant query is prevented at the
  access policy level (principal scoped to tenant-specific index patterns).

This is a required constraint, not an optional configuration.

### Memory Lifecycle

| Memory type | Storage location | Lifecycle |
|-------------|-----------------|-----------|
| Short-term context (sliding window tokens) | Compute state (ECS/Lambda working memory) | Discarded when container terminates |
| Mid-run execution state | EFS write-ahead (spec-09) → DynamoDB (spec-03) | 30-day TTL via spec-03 |
| Long-term episodic memory (summaries, facts) | DynamoDB memory table (spec-03) | 90-day TTL via spec-03 |
| Knowledge base (documents, FAQs) | Vector store (this spec) | Client-controlled TTL or explicit delete |

spec-06 handles the knowledge base tier only. Session and episodic memory are in spec-03.

### Framework-Agnostic Output Contract

All active backends produce the same Terraform outputs:
- `vector_endpoint` — connection string or API URL
- `collection_id` — identifier for the vector collection
- `embedding_model_id` — model used to generate embeddings (must match query-time model)

Changing the backend = update config + re-apply. Zero framework code change.

---

## `accounts.tf.json` Contract

```json
"vector-store": {
  "vector_store_config_json": {
    "backends": ["pgvector"],
    "pgvector": {
      "schema_name": "vectors",
      "tenant_isolation": "rls",
      "embedding_dimensions": 1536,
      "index_type": "hnsw",
      "index_m": 16,
      "index_ef_construction": 64,
      "embedding_model": "amazon.titan-embed-text-v2:0"
    },
    "opensearch_serverless": {
      "collection_name_suffix": "knowledge",
      "type": "VECTORSEARCH",
      "standby_replicas": false,
      "tenant_isolation": "per-index",
      "embedding_dimensions": 1536,
      "embedding_model": "amazon.titan-embed-text-v2:0"
    },
    "bedrock_kb": {
      "name_suffix": "knowledge",
      "embedding_model": "amazon.titan-embed-text-v2:0",
      "chunking_strategy": "fixed",
      "chunk_size": 300,
      "chunk_overlap": 20,
      "data_source_bucket_key": "knowledge_docs"
    }
  }
}
```

**`backends`**: Array of active backends. Valid values: `"pgvector"`, `"opensearch-serverless"`, `"bedrock-kb"`.
- `["pgvector"]` — pgvector only (default, MVP)
- `["pgvector", "opensearch-serverless"]` — both active simultaneously (scale)
- `["bedrock-kb"]` — fully managed (replaces pgvector)

**`tenant_isolation`**:
- pgvector: `"rls"` (Row Level Security per tenant) or `"schema"` (separate schema per tenant)
- opensearch: `"per-index"` (separate index per tenant) — required, no single-index option

---

## Workspace Structure

```
workspaces/vector-store/
  main.tf          ← Conditional: pgvector extension Lambda | OpenSearch collection | Bedrock KB
  variables.tf     ← vector_store_config_json (decoded)
  outputs.tf       ← vector_endpoint, collection_id, embedding_model_id (unified interface)
  data.tf          ← vpc, rds (pgvector), bedrock (bedrock-kb), ai-storage (bedrock-kb)
  pgvector/
    setup.sql      ← DDL: CREATE EXTENSION, CREATE TABLE, CREATE INDEX
    migration_lambda.py  ← Lambda that runs setup.sql against RDS Proxy
```

---

## Sample Terraform

### Conditional Backend Selection

```hcl
locals {
  config         = jsondecode(var.vector_store_config_json)
  use_pgvector   = local.config.backend == "pgvector"
  use_opensearch = local.config.backend == "opensearch-serverless"
  use_bedrock_kb = local.config.backend == "bedrock-kb"
}
```

### Backend A: pgvector (extends existing RDS)

```hcl
# pgvector is enabled via a migration Lambda that runs SQL against the existing RDS
# No new AWS resource is created — this extends spec-rds via the RDS Proxy

resource "aws_lambda_function" "pgvector_setup" {
  count         = local.use_pgvector ? 1 : 0
  function_name = "${var.client_id}-${var.env}-pgvector-setup"
  role          = aws_iam_role.pgvector_setup[0].arn
  runtime       = "python3.12"
  handler       = "migration_lambda.handler"
  filename      = data.archive_file.pgvector_setup[0].output_path

  environment {
    variables = {
      DB_PROXY_ENDPOINT  = data.tfe_outputs.rds.outputs.proxy_endpoint
      DB_NAME            = data.tfe_outputs.rds.outputs.db_name
      DB_IAM_USERNAME    = "vector_store"
      VECTOR_SCHEMA      = local.config.pgvector.schema_name
      VECTOR_DIMENSIONS  = local.config.pgvector.embedding_dimensions
      INDEX_TYPE         = local.config.pgvector.index_type
    }
  }

  vpc_config {
    subnet_ids         = data.tfe_outputs.vpc.outputs.private_subnet_ids
    security_group_ids = [aws_security_group.pgvector_setup[0].id]
  }
}

# Invoke the setup Lambda once on apply (null_resource trigger)
resource "terraform_data" "pgvector_setup" {
  count = local.use_pgvector ? 1 : 0

  triggers_replace = [
    local.config.pgvector.schema_name,
    local.config.pgvector.embedding_dimensions,
    local.config.pgvector.index_type
  ]

  provisioner "local-exec" {
    command = "aws lambda invoke --function-name ${aws_lambda_function.pgvector_setup[0].function_name} --payload '{}' /tmp/pgvector-setup-result.json"
  }

  depends_on = [aws_lambda_function.pgvector_setup]
}
```

```sql
-- workspaces/vector-store/pgvector/setup.sql (executed by migration Lambda)
CREATE EXTENSION IF NOT EXISTS vector;

CREATE SCHEMA IF NOT EXISTS vectors;

CREATE TABLE IF NOT EXISTS vectors.documents (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   TEXT NOT NULL,               -- multi-tenant isolation
  collection  TEXT NOT NULL DEFAULT 'default',
  content     TEXT NOT NULL,
  metadata    JSONB DEFAULT '{}',
  embedding   VECTOR(1536),               -- dimension must match embedding model
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- HNSW index for fast approximate nearest-neighbor search
CREATE INDEX IF NOT EXISTS documents_embedding_hnsw
  ON vectors.documents
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- Tenant-scoped lookup index
CREATE INDEX IF NOT EXISTS documents_tenant_collection
  ON vectors.documents (tenant_id, collection);
```

### Backend B: OpenSearch Serverless

```hcl
resource "aws_opensearchserverless_security_policy" "encryption" {
  count = local.use_opensearch ? 1 : 0
  name  = "${var.client_id}-${var.env}-vectors-enc"
  type  = "encryption"

  policy = jsonencode({
    Rules = [{ ResourceType = "collection", Resource = ["collection/${var.client_id}-${var.env}-knowledge"] }]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_collection" "vectors" {
  count = local.use_opensearch ? 1 : 0
  name  = "${var.client_id}-${var.env}-knowledge"
  type  = "VECTORSEARCH"

  standby_replicas = local.config.opensearch_serverless.standby_replicas ? "ENABLED" : "DISABLED"

  depends_on = [aws_opensearchserverless_security_policy.encryption]
}

resource "aws_opensearchserverless_access_policy" "vectors" {
  count = local.use_opensearch ? 1 : 0
  name  = "${var.client_id}-${var.env}-vectors-access"
  type  = "data"

  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${aws_opensearchserverless_collection.vectors[0].name}"]
        Permission   = ["aoss:CreateCollectionItems", "aoss:DeleteCollectionItems",
                        "aoss:UpdateCollectionItems", "aoss:DescribeCollectionItems"]
      },
      {
        ResourceType = "index"
        Resource     = ["index/${aws_opensearchserverless_collection.vectors[0].name}/*"]
        Permission   = ["aoss:CreateIndex", "aoss:DeleteIndex", "aoss:UpdateIndex",
                        "aoss:DescribeIndex", "aoss:ReadDocument", "aoss:WriteDocument"]
      }
    ]
    Principal = [data.tfe_outputs.iam.outputs.ai_engine_role_arn]
  }])
}
```

### Backend C: Bedrock Knowledge Base (Fully Managed)

```hcl
resource "aws_iam_role" "bedrock_kb" {
  count = local.use_bedrock_kb ? 1 : 0
  name  = "${var.client_id}-${var.env}-bedrock-kb"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_bedrockagent_knowledge_base" "docs" {
  count    = local.use_bedrock_kb ? 1 : 0
  name     = "${var.client_id}-${var.env}-${local.config.bedrock_kb.name_suffix}"
  role_arn = aws_iam_role.bedrock_kb[0].arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.region}::foundation-model/${local.config.bedrock_kb.embedding_model}"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.bedrock_kb_collection[0].arn
      vector_index_name = "bedrock-knowledge-base-default-index"
      field_mapping {
        vector_field   = "bedrock-knowledge-base-default-vector"
        text_field     = "AMAZON_BEDROCK_TEXT_CHUNK"
        metadata_field = "AMAZON_BEDROCK_METADATA"
      }
    }
  }
}

resource "aws_bedrockagent_data_source" "s3" {
  count              = local.use_bedrock_kb ? 1 : 0
  knowledge_base_id  = aws_bedrockagent_knowledge_base.docs[0].id
  name               = "s3-documents"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = data.tfe_outputs.ai_storage.outputs.knowledge_docs_bucket_arn
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = upper(local.config.bedrock_kb.chunking_strategy)
      fixed_size_chunking_configuration {
        max_tokens         = local.config.bedrock_kb.chunk_size
        overlap_percentage = local.config.bedrock_kb.chunk_overlap
      }
    }
  }
}
```

### Unified Outputs

```hcl
output "vector_endpoint" {
  description = "Vector store connection endpoint — backend-specific format"
  value = (
    local.use_pgvector   ? data.tfe_outputs.rds.outputs.proxy_endpoint :
    local.use_opensearch ? aws_opensearchserverless_collection.vectors[0].collection_endpoint :
    local.use_bedrock_kb ? aws_bedrockagent_knowledge_base.docs[0].id :
    null
  )
}

output "collection_id" {
  description = "Vector collection identifier"
  value = (
    local.use_pgvector   ? "${local.config.pgvector.schema_name}.documents" :
    local.use_opensearch ? aws_opensearchserverless_collection.vectors[0].id :
    local.use_bedrock_kb ? aws_bedrockagent_knowledge_base.docs[0].id :
    null
  )
}

output "embedding_model_id" {
  description = "Embedding model ID — use this model for all query-time embeddings (must match ingest-time model)"
  value = (
    local.use_pgvector   ? local.config.pgvector.embedding_model :
    local.use_opensearch ? local.config.opensearch_serverless.embedding_model :
    local.use_bedrock_kb ? local.config.bedrock_kb.embedding_model :
    null
  )
}

output "backend" {
  description = "Active vector store backend"
  value       = local.config.backend
}
```

---

## IAM Permissions Required (Bootstrap Role)

```
# pgvector
lambda:CreateFunction, lambda:InvokeFunction, lambda:DeleteFunction

# opensearch-serverless
aoss:CreateCollection, aoss:DeleteCollection
aoss:CreateSecurityPolicy, aoss:CreateAccessPolicy

# bedrock-kb
bedrock:CreateKnowledgeBase, bedrock:DeleteKnowledgeBase
bedrock:CreateDataSource, bedrock:StartIngestionJob
iam:CreateRole, iam:AttachRolePolicy, iam:PassRole
```

---

## Todos

### Infrastructure
- [ ] Create `workspaces/vector-store/` directory
- [ ] Create `workspaces/vector-store/main.tf` — conditional backend logic
- [ ] Create `workspaces/vector-store/pgvector/setup.sql` — DDL for pgvector schema
- [ ] Create `workspaces/vector-store/pgvector/migration_lambda.py` — Lambda that runs DDL
- [ ] Create `workspaces/vector-store/variables.tf` — `vector_store_config_json` variable
- [ ] Create `workspaces/vector-store/outputs.tf` — unified outputs for all backends

### Control Plane Wiring
- [ ] Add `vector-store` to `service_working_dirs` map
- [ ] Add dependency rules:
  - pgvector: requires `rds` and `vpc`
  - opensearch-serverless: requires `vpc` and `iam`
  - bedrock-kb: requires `bedrock` and `ai-storage`
- [ ] Add `vector_store_config_json` schema validation (valid `backend` values)

### Test Client
- [ ] Add `vector-store` to `test-client-dev` services with `backend: "pgvector"`
- [ ] Apply and verify pgvector extension + table exist in RDS
- [ ] Run a sample embedding insert + similarity query

---

## Verification

```bash
# Backend A: pgvector
# Check via a bastion Lambda or RDS query tool
psql $DATABASE_URL -c "\dx vector"
# Expected: vector extension listed

psql $DATABASE_URL -c "\d vectors.documents"
# Expected: table with embedding column of type vector(1536)

# Backend B: OpenSearch Serverless
aws opensearchserverless get-collection \
  --id $(terraform output -raw collection_id) \
  --query "collectionDetails.status"
# Expected: "ACTIVE"

# Backend C: Bedrock KB
aws bedrock-agent get-knowledge-base \
  --knowledge-base-id $(terraform output -raw collection_id) \
  --query "knowledgeBase.status"
# Expected: "ACTIVE"
```

**Gate:** Active vector store with correct schema; test document insert + similarity query succeeds.

---

## Cost Notes

| Backend | Idle cost | Per-query cost |
|---|---|---|
| pgvector | +$0 (reuses existing RDS) | Near zero (RDS compute) |
| OpenSearch Serverless | ~$700/month (2 OCU minimum) | $0.24/OCU-hour for search |
| Bedrock Knowledge Base | $0 | $0.10-$0.30 per document sync; $0.10/1K retrieved chunks |

For MVP clients: **always start with pgvector**. Migrate to OpenSearch Serverless when:
- Vector count exceeds 5M documents
- Multi-tenant isolation per collection is required
- Query latency at scale becomes unacceptable
