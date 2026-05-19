# Spec-03: Agent State

**Status:** `[ ] not started`
**Phase:** Wave 1 — Serverless AI Foundations
**Depends on:** `iam`
**Blocks:** `spec-09-ecs` (ECS task roles need table ARNs to scope DynamoDB access), `spec-15-dynamic-iam` (base execution role scoped to these table ARNs)
**Repo(s):** core-tfe-bootstrap-workspace-management

---

## Business Rule

Agent execution state must persist durably so that agents resume at their last checkpoint
rather than restarting from scratch when compute is recycled, rate-limited, or restarted.

---

## Goal

Provision durable, serverless storage for agent execution state:
- **Checkpoints table**: Saves agent execution snapshots mid-run (current step, tool outputs, variable context)
- **Memory table**: Stores cross-session knowledge (facts, preferences, conversation summaries)

Both tables use DynamoDB PAY_PER_REQUEST billing — $0 at zero traffic.
Both are framework-agnostic: any AI framework implements its own DynamoDB adapter.

---

## Context

AI agents need to resume, not restart. A user mid-conversation must pick up exactly where
they left off, even if the Lambda cold-started or the ECS task was replaced.

**Checkpoint vs Memory distinction:**

| Table | Purpose | TTL | Partition key pattern |
|---|---|---|---|
| `agent-checkpoints` | Mid-run execution snapshots (LangGraph nodes, step outputs) | 30 days | `tenant_id#session_id` |
| `agent-memory` | Cross-session knowledge (facts the agent learns about the user) | 90 days | `tenant_id#entity_id` |

**PlatformContext key design**: Partition key format is `{tenant_id}#{session_id}` — never just
`session_id`. This enforces multi-tenant data isolation at the database level. An agent can only
read its own tenant's data by construction of the key, not just by IAM policy.

**Framework-agnostic**: This blueprint creates tables and outputs their names and ARNs. The AI
framework is responsible for implementing a DynamoDB adapter using the table name from an
environment variable. The infrastructure contract is the table name and key schema — not the
framework library used to access it.

### State Ledger Model

The checkpoints table is a **state ledger**, not just a snapshot store. Each item captures:
- `current_step` — step number in the execution graph
- `tool_outputs` — results from all tool calls completed so far
- `variable_context` — agent working memory (inputs, intermediate values)
- `decision_history` — list of decisions made and branches taken
- `execution_id` — unique ID for this execution run (used for idempotency)

This structure allows any newly-spawned compute instance to hydrate the agent's exact state
and resume from the last committed step.

### Idempotency Pattern

SQS delivers messages at-least-once. Without idempotency protection, a retried SQS message
could cause an agent to execute the same tool twice. The DynamoDB write pattern must enforce:

```
Write condition: attribute_not_exists(execution_id) OR step_number < :new_step_number
```

Required fields on every checkpoint write:
- `execution_id` (string) — unique per agent invocation (UUID generated at task start)
- `step_number` (number) — monotonically increasing per execution graph step

If a write fails the condition, the step was already committed — the retry is a duplicate.

### Optimistic Locking

Concurrent sub-agents (parallel tool calls) must not overwrite each other's state. Implement
optimistic locking via a `version` attribute:

```
UpdateExpression: SET version = version + 1, step_data = :new_data
ConditionExpression: version = :expected_version
```

If the condition fails, another sub-agent updated the record — the caller must re-read and retry.

### EFS Write-Ahead (spec-09 cross-reference)

ECS Fargate containers (spec-09) mount an EFS volume for in-flight agent state (local
variables mid-loop that have not yet been committed to DynamoDB). If a container is recycled
before the DynamoDB write completes, the next container reads from EFS as the write-ahead log
and reattempts the commit. EFS is transient; DynamoDB is the durable ledger.

---

## `accounts.tf.json` Contract

```json
"agent-state": {
  "agent_state_config_json": {
    "billing_mode": "PAY_PER_REQUEST",
    "tables": {
      "checkpoints": {
        "name_suffix": "agent-checkpoints",
        "ttl_days": 30,
        "enable_streams": true,
        "enable_pitr": true
      },
      "memory": {
        "name_suffix": "agent-memory",
        "ttl_days": 90,
        "enable_streams": false,
        "enable_pitr": true
      }
    }
  }
}
```

**`enable_streams`**: Set to `true` on `checkpoints` so downstream consumers (e.g. an audit
Lambda, or an EventBridge Pipe triggering on state changes) can react to checkpoint events.

---

## Workspace Structure

```
workspaces/agent-state/
  main.tf          ← DynamoDB tables, TTL, streams, PITR
  variables.tf     ← agent_state_config_json (decoded)
  outputs.tf       ← table names, table ARNs, stream ARNs
  data.tf          ← data.tfe_outputs.iam, data.tfe_outputs.secure_baseline
```

---

## Sample Terraform

### DynamoDB Tables

```hcl
locals {
  tables = jsondecode(var.agent_state_config_json)
}

resource "aws_dynamodb_table" "tables" {
  for_each = local.tables.tables

  name         = "${var.client_id}-${var.env}-${each.value.name_suffix}"
  billing_mode = local.tables.billing_mode

  # Composite primary key: tenant-scoped partition + time-ordered sort
  hash_key  = "pk"  # "tenant_id#session_id" or "tenant_id#entity_id"
  range_key = "sk"  # "checkpoint#<sequence>" or "fact#<timestamp>"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  # TTL — agents expire automatically, no cleanup Lambda needed
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  # PITR — point-in-time recovery for compliance and accidental-delete recovery
  point_in_time_recovery {
    enabled = each.value.enable_pitr
  }

  # Streams — enables downstream consumers (audit, EventBridge Pipes)
  stream_enabled   = each.value.enable_streams
  stream_view_type = each.value.enable_streams ? "NEW_AND_OLD_IMAGES" : null

  # Encryption with secure-baseline KMS key
  server_side_encryption {
    enabled     = true
    kms_key_arn = data.tfe_outputs.secure_baseline.outputs.kms_key_arn
  }

  tags = merge(var.tags, {
    Name      = "${var.client_id}-${var.env}-${each.value.name_suffix}"
    client_id = var.client_id
    env       = var.env
    blueprint = "agent-state"
  })
}
```

### IAM Access Policies

```hcl
# Read-write policy — for ECS tasks and Lambda functions running agents
resource "aws_iam_policy" "agent_state_readwrite" {
  name        = "${var.client_id}-${var.env}-agent-state-rw"
  description = "Read-write access to agent state DynamoDB tables"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TableReadWrite"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:ConditionCheckItem"
        ]
        Resource = concat(
          [for k, t in aws_dynamodb_table.tables : t.arn],
          [for k, t in aws_dynamodb_table.tables : "${t.arn}/index/*"]
        )
      },
      {
        Sid    = "StreamRead"
        Effect = "Allow"
        Action = [
          "dynamodb:GetShardIterator",
          "dynamodb:GetRecords",
          "dynamodb:ListStreams",
          "dynamodb:DescribeStream"
        ]
        Resource = [for k, t in aws_dynamodb_table.tables :
          t.stream_arn if t.stream_enabled]
      },
      {
        Sid    = "DecryptKms"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = [data.tfe_outputs.secure_baseline.outputs.kms_key_arn]
      }
    ]
  })
}

# Read-only policy — for observability/audit consumers
resource "aws_iam_policy" "agent_state_readonly" {
  name = "${var.client_id}-${var.env}-agent-state-ro"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:BatchGetItem"]
      Resource = [for k, t in aws_dynamodb_table.tables : t.arn]
    }]
  })
}
```

### Example: How a Framework Uses These Tables

```python
# In forge-core-ai (Python) — LangGraph checkpointer wiring
# The table name comes from environment variable, never hardcoded

import os
from langgraph.checkpoint.dynamodb import DynamoDBSaver

checkpointer = DynamoDBSaver(
    table_name=os.environ["AGENT_CHECKPOINTS_TABLE"],  # from ECS/Lambda env var
    # Partition key prefix enforces tenant isolation
    # pk = f"{platform_context.tenant_id}#{session_id}"
)
```

```typescript
// In forge-core (NestJS) — custom state adapter for non-LangGraph agents
// table name injected from SecretsManager or env var, sourced from Terraform output

const checkpointKey = {
  pk: `${platformContext.tenantId}#${sessionId}`,
  sk: `checkpoint#${Date.now()}`
};
```

---

## IAM Permissions Required (Bootstrap Role)

```
dynamodb:CreateTable
dynamodb:DeleteTable
dynamodb:DescribeTable
dynamodb:UpdateTable
dynamodb:UpdateTimeToLive
dynamodb:DescribeContinuousBackups
dynamodb:UpdateContinuousBackups
iam:CreatePolicy
iam:GetPolicy
iam:DeletePolicy
```

---

## Outputs

```hcl
output "checkpoints_table_name" {
  description = "DynamoDB table name for agent checkpoints — inject as AGENT_CHECKPOINTS_TABLE env var"
  value       = aws_dynamodb_table.tables["checkpoints"].name
}

output "checkpoints_table_arn" {
  description = "DynamoDB table ARN — used to scope IAM policies"
  value       = aws_dynamodb_table.tables["checkpoints"].arn
}

output "checkpoints_stream_arn" {
  description = "DynamoDB stream ARN for checkpoints — for EventBridge Pipes or Lambda triggers"
  value       = aws_dynamodb_table.tables["checkpoints"].stream_arn
}

output "memory_table_name" {
  description = "DynamoDB table name for cross-session agent memory — inject as AGENT_MEMORY_TABLE env var"
  value       = aws_dynamodb_table.tables["memory"].name
}

output "memory_table_arn" {
  description = "DynamoDB table ARN"
  value       = aws_dynamodb_table.tables["memory"].arn
}

output "readwrite_policy_arn" {
  description = "IAM policy ARN for agent state read-write — attach to ECS task role or Lambda role"
  value       = aws_iam_policy.agent_state_readwrite.arn
}

output "readonly_policy_arn" {
  description = "IAM policy ARN for agent state read-only — attach to observability consumers"
  value       = aws_iam_policy.agent_state_readonly.arn
}
```

---

## Todos

### Infrastructure
- [ ] Create `workspaces/agent-state/` directory
- [ ] Create `workspaces/agent-state/main.tf` — DynamoDB tables + IAM policies
- [ ] Create `workspaces/agent-state/variables.tf` — `agent_state_config_json` variable
- [ ] Create `workspaces/agent-state/outputs.tf`
- [ ] Create `workspaces/agent-state/data.tf` — secure_baseline outputs (KMS key ARN)

### Control Plane Wiring
- [ ] Add `agent-state` to `service_working_dirs` map
- [ ] Add dependency: requires `secure-baseline` (KMS) and `iam` workspaces
- [ ] Add `agent_state_config_json` schema validation (valid `billing_mode` values)

### Consumer Wiring (in forge-core-ai / forge-core)
- [ ] Add `AGENT_CHECKPOINTS_TABLE` and `AGENT_MEMORY_TABLE` to ECS task env vars
- [ ] Add `AGENT_CHECKPOINTS_TABLE` and `AGENT_MEMORY_TABLE` to Lambda env vars
- [ ] Attach `readwrite_policy_arn` output to ECS task role and Lambda execution role

### Test Client
- [ ] Add `agent-state` to `test-client-dev` services
- [ ] Apply workspace and verify both tables exist in DynamoDB console
- [ ] Write a test item with `pk = "test-tenant#test-session"` and verify TTL is set

---

## Verification

```bash
# 1. List tables — confirm both tables created
aws dynamodb list-tables \
  --query "TableNames[?contains(@, 'test-client-dev-agent')]"
# Expected: ["test-client-dev-agent-checkpoints", "test-client-dev-agent-memory"]

# 2. Confirm TTL enabled on checkpoints table
aws dynamodb describe-time-to-live \
  --table-name test-client-dev-agent-checkpoints \
  --query "TimeToLiveDescription.TimeToLiveStatus"
# Expected: "ENABLED"

# 3. Confirm PITR enabled
aws dynamodb describe-continuous-backups \
  --table-name test-client-dev-agent-checkpoints \
  --query "ContinuousBackupsDescription.PointInTimeRecoveryDescription.PointInTimeRecoveryStatus"
# Expected: "ENABLED"

# 4. Confirm streams enabled (for checkpoints)
aws dynamodb describe-table \
  --table-name test-client-dev-agent-checkpoints \
  --query "Table.StreamSpecification.StreamEnabled"
# Expected: true

# 5. Write and read test item
aws dynamodb put-item \
  --table-name test-client-dev-agent-checkpoints \
  --item '{"pk":{"S":"test-tenant#test-session"},"sk":{"S":"checkpoint#001"},"data":{"S":"hello"},"expires_at":{"N":"9999999999"}}'

aws dynamodb get-item \
  --table-name test-client-dev-agent-checkpoints \
  --key '{"pk":{"S":"test-tenant#test-session"},"sk":{"S":"checkpoint#001"}}' \
  --query "Item.data.S"
# Expected: "hello"
```

**Gate:** Both tables exist, TTL and PITR confirmed enabled, read/write test item succeeds.

---

## Cost Notes

| Resource | Cost |
|---|---|
| DynamoDB table (PAY_PER_REQUEST) | $0 idle |
| Read request units | $0.25 per million RRUs |
| Write request units | $1.25 per million WRUs |
| Storage | $0.25/GB/month |
| DynamoDB Streams | $0.02 per 100K stream read requests |
| PITR (per table) | $0.20/GB/month of data stored |

**At 1K agent sessions/day** (~50K checkpoint writes/day): ~$0.10/day in write costs.
Cost scales linearly with usage — no minimum commitment.
