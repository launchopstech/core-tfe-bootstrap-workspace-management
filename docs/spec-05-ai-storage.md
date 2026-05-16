# Spec-05: AI Storage

**Status:** `[ ] not started`
**Phase:** Wave 1 — Serverless AI Foundations
**Depends on:** `iam`, `secure-baseline` (KMS key)
**Blocks:** Fine-tuning pipeline (post-MVP spec)
**Repo(s):** core-tfe-bootstrap-workspace-management

---

## Goal

Provision S3 buckets as the storage foundation for AI workloads:
- **training-data** — raw training corpora, labeled datasets, evaluation sets
- **model-artifacts** — base model weights, fine-tuned checkpoints, ONNX exports
- **adapter-weights** — LoRA/QLoRA adapter files (MB-scale per adapter, fast swap)
- **knowledge-docs** — raw documents for RAG ingestion (consumed by `spec-06-vector-store`)

This spec creates the storage layer only. The processing pipelines (SageMaker, LiteLLM
adapter loading, document ingestion) are in separate downstream specs.

---

## Context

Fine-tuning with LoRA/QLoRA adapters is a cost-effective way to add domain-specific behavior
without full retraining. An adapter for tone or terminology is typically 10-100MB — trivially
stored in S3 and swapped at runtime.

**Why create storage now, before the pipeline?**

The storage buckets have zero cost at rest (only charged for data stored and requests). Creating
them now:
1. Unblocks clients from uploading training data immediately
2. Establishes naming and encryption policy before data arrives
3. Allows the knowledge-docs bucket to be referenced by `spec-06-vector-store`
4. Zero cost to have empty buckets

**Decagon-derived insight**: The Decagon research showed RAG + system prompts beat fine-tuning
for most tasks. Fine-tuning (via LoRA) is reserved for behavioral adaptation (tone, schema).
The storage blueprint supports both paths from day one.

---

## `accounts.tf.json` Contract

```json
"ai-storage": {
  "ai_storage_config_json": {
    "buckets": {
      "training_data": {
        "name_suffix": "ai-training-data",
        "versioning": true,
        "lifecycle_noncurrent_days": 30,
        "intelligent_tiering": true
      },
      "model_artifacts": {
        "name_suffix": "ai-model-artifacts",
        "versioning": true,
        "lifecycle_noncurrent_days": 90,
        "intelligent_tiering": false
      },
      "adapter_weights": {
        "name_suffix": "ai-adapter-weights",
        "versioning": true,
        "lifecycle_noncurrent_days": 60,
        "intelligent_tiering": false
      },
      "knowledge_docs": {
        "name_suffix": "ai-knowledge-docs",
        "versioning": false,
        "lifecycle_noncurrent_days": 0,
        "intelligent_tiering": true
      }
    }
  }
}
```

**`versioning`**: Enabled on training data and artifacts — never lose a training set or model
checkpoint. Knowledge docs don't need versioning (source of truth is the ingested vector store).

**`intelligent_tiering`**: Automatically moves infrequently accessed objects to cheaper storage
classes. Useful for training data that is written once and rarely re-read.

---

## Workspace Structure

```
workspaces/ai-storage/
  main.tf      ← S3 buckets, versioning, lifecycle, encryption, public access block
  variables.tf ← ai_storage_config_json (decoded)
  outputs.tf   ← bucket names, bucket ARNs, knowledge_docs_bucket_name
  data.tf      ← data.tfe_outputs.secure_baseline (KMS key)
```

---

## Sample Terraform

### S3 Buckets

```hcl
locals {
  config = jsondecode(var.ai_storage_config_json)
}

resource "aws_s3_bucket" "buckets" {
  for_each = local.config.buckets

  bucket = "${var.client_id}-${var.env}-${each.value.name_suffix}"

  tags = merge(var.tags, {
    Name      = "${var.client_id}-${var.env}-${each.value.name_suffix}"
    blueprint = "ai-storage"
    bucket    = each.key
  })
}

# Block all public access — non-negotiable for AI training data
resource "aws_s3_bucket_public_access_block" "buckets" {
  for_each = local.config.buckets

  bucket                  = aws_s3_bucket.buckets[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# KMS encryption — use secure-baseline key
resource "aws_s3_bucket_server_side_encryption_configuration" "buckets" {
  for_each = local.config.buckets

  bucket = aws_s3_bucket.buckets[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = data.tfe_outputs.secure_baseline.outputs.kms_key_arn
    }
    bucket_key_enabled = true  # Reduces KMS API call costs by ~99%
  }
}

# Versioning
resource "aws_s3_bucket_versioning" "buckets" {
  for_each = { for k, b in local.config.buckets : k => b if b.versioning }

  bucket = aws_s3_bucket.buckets[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle rules — expire non-current versions
resource "aws_s3_bucket_lifecycle_configuration" "buckets" {
  for_each = { for k, b in local.config.buckets : k => b if b.versioning && b.lifecycle_noncurrent_days > 0 }

  bucket = aws_s3_bucket.buckets[each.key].id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = each.value.lifecycle_noncurrent_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Intelligent Tiering — for infrequently accessed data
resource "aws_s3_bucket_intelligent_tiering_configuration" "buckets" {
  for_each = { for k, b in local.config.buckets : k => b if b.intelligent_tiering }

  bucket = aws_s3_bucket.buckets[each.key].id
  name   = "EntireBucket"
  status = "Enabled"

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }
}
```

### IAM Access Policies

```hcl
# Read-write for training pipelines and artifact uploaders
resource "aws_iam_policy" "ai_storage_readwrite" {
  name        = "${var.client_id}-${var.env}-ai-storage-rw"
  description = "Read-write access to AI storage buckets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBuckets"
        Effect = "Allow"
        Action = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [for k, b in aws_s3_bucket.buckets : b.arn]
      },
      {
        Sid    = "ReadWriteObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = [for k, b in aws_s3_bucket.buckets : "${b.arn}/*"]
      },
      {
        Sid    = "KmsAccess"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = [data.tfe_outputs.secure_baseline.outputs.kms_key_arn]
      }
    ]
  })
}

# Read-only for RAG ingestion pipelines (vector-store spec)
resource "aws_iam_policy" "knowledge_docs_readonly" {
  name = "${var.client_id}-${var.env}-knowledge-docs-ro"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.buckets["knowledge_docs"].arn,
          "${aws_s3_bucket.buckets["knowledge_docs"].arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = [data.tfe_outputs.secure_baseline.outputs.kms_key_arn]
      }
    ]
  })
}
```

---

## IAM Permissions Required (Bootstrap Role)

```
s3:CreateBucket
s3:DeleteBucket
s3:PutBucketVersioning
s3:PutBucketEncryption
s3:PutBucketPublicAccessBlock
s3:PutLifecycleConfiguration
s3:PutIntelligentTieringConfiguration
s3:PutBucketTagging
iam:CreatePolicy
iam:DeletePolicy
```

---

## Outputs

```hcl
output "bucket_names" {
  description = "Map of bucket key → bucket name"
  value       = { for k, b in aws_s3_bucket.buckets : k => b.id }
}

output "bucket_arns" {
  description = "Map of bucket key → bucket ARN"
  value       = { for k, b in aws_s3_bucket.buckets : k => b.arn }
}

output "knowledge_docs_bucket_name" {
  description = "Knowledge docs bucket name — used by spec-06-vector-store as RAG data source"
  value       = aws_s3_bucket.buckets["knowledge_docs"].id
}

output "knowledge_docs_bucket_arn" {
  description = "Knowledge docs bucket ARN"
  value       = aws_s3_bucket.buckets["knowledge_docs"].arn
}

output "readwrite_policy_arn" {
  description = "IAM policy ARN for full read-write — attach to training pipeline roles"
  value       = aws_iam_policy.ai_storage_readwrite.arn
}

output "knowledge_docs_readonly_policy_arn" {
  description = "IAM policy ARN for knowledge docs read-only — attach to RAG ingestion roles"
  value       = aws_iam_policy.knowledge_docs_readonly.arn
}
```

---

## Todos

### Infrastructure
- [ ] Create `workspaces/ai-storage/` directory
- [ ] Create `workspaces/ai-storage/main.tf` — 4 buckets with encryption, versioning, lifecycle
- [ ] Create `workspaces/ai-storage/variables.tf` — `ai_storage_config_json` variable
- [ ] Create `workspaces/ai-storage/outputs.tf`
- [ ] Create `workspaces/ai-storage/data.tf` — secure-baseline outputs (KMS key)

### Control Plane Wiring
- [ ] Add `ai-storage` to `service_working_dirs` map
- [ ] Add dependency: requires `secure-baseline` and `iam` workspaces
- [ ] Expose `knowledge_docs_bucket_name` output — consumed by `spec-06-vector-store` (bedrock-kb backend)

### Test Client
- [ ] Add `ai-storage` to `test-client-dev` services
- [ ] Apply workspace and verify all 4 buckets exist with encryption and public access blocked

---

## Verification

```bash
# 1. List AI storage buckets
aws s3api list-buckets \
  --query "Buckets[?contains(Name, 'test-client-dev-ai')].Name"
# Expected: 4 bucket names

# 2. Confirm public access is blocked
aws s3api get-public-access-block \
  --bucket "test-client-dev-ai-training-data" \
  --query "PublicAccessBlockConfiguration"
# Expected: all 4 fields = true

# 3. Confirm KMS encryption
aws s3api get-bucket-encryption \
  --bucket "test-client-dev-ai-training-data" \
  --query "ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm"
# Expected: "aws:kms"

# 4. Confirm versioning enabled on training-data
aws s3api get-bucket-versioning \
  --bucket "test-client-dev-ai-training-data" \
  --query "Status"
# Expected: "Enabled"

# 5. Upload a test file and confirm it lands encrypted
echo "test" | aws s3 cp - s3://test-client-dev-ai-knowledge-docs/test.txt
aws s3api head-object \
  --bucket "test-client-dev-ai-knowledge-docs" \
  --key "test.txt" \
  --query "ServerSideEncryption"
# Expected: "aws:kms"
```

**Gate:** All 4 buckets exist, public access blocked, KMS encryption confirmed, test upload succeeds.

---

## Cost Notes

| Resource | Cost |
|---|---|
| S3 Standard storage | $0.023/GB/month |
| S3 Intelligent-Tiering (frequent access tier) | $0.023/GB/month |
| S3 Intelligent-Tiering (infrequent access tier, >30 days) | $0.0125/GB/month |
| S3 Intelligent-Tiering (archive, >90 days) | $0.004/GB/month |
| S3 versioning overhead | ~10-20% storage increase if frequent updates |
| PUT/COPY requests | $0.005 per 1K requests |

**At rest with empty buckets: $0/month.** Cost scales only with actual data stored.

Post-MVP fine-tuning pipeline will add SageMaker training job costs (billed by compute time).
