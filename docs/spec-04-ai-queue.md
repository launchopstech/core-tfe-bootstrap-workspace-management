# Spec-04: AI Queue

**Status:** `[ ] not started`
**Phase:** Wave 1 — Serverless AI Foundations
**Depends on:** `iam`, `secure-baseline` (KMS key)
**Blocks:** `spec-09-ecs` (ECS auto-scaling uses queue depth metric)
**Repo(s):** core-tfe-bootstrap-workspace-management

---

## Goal

Provision SQS queues for:
1. **Async task dispatch** — decouple API responses from long-running agent tasks
2. **Human-in-the-loop (HITL) approval gates** — agent pauses, human reviews, agent resumes
3. **Dead-letter queues** — capture failed or timed-out tasks for debugging

---

## Context

AI agents are not instant. A complex multi-step task (research → draft → review → send)
may take 30 seconds to 10 minutes. The API cannot wait.

**Async pattern**:
```
Client → POST /api/tasks             → API returns 202 + task_id (immediately)
                                      → ai-tasks SQS queue receives message
                                      → Worker Lambda/ECS picks up task
                                      → Worker calls ai-gateway for model calls
                                      → Worker updates agent-state (DynamoDB)
Client → GET /api/tasks/{task_id}    → Returns status + partial results
Client → WebSocket / SSE stream      → Receives streaming updates
```

**HITL pattern**:
```
Agent encounters decision requiring human approval
  → Agent writes to ai-hitl FIFO queue (ordered, exactly-once)
  → Pauses execution, saves checkpoint to agent-state
  → Human reviews in management UI
  → Human POSTs approval/rejection to API
  → API sends message back to HITL queue (or wakes up Step Function)
  → Agent resumes from checkpoint
```

**Why separate queues?**
- `ai-tasks` is a standard queue — high throughput, at-least-once delivery, unordered
- `ai-hitl` is FIFO — ordered, exactly-once, critical for audit trail

**Dead-letter queues**: Every queue has a DLQ. Failed tasks go here after N receive attempts.
The DLQ retention is 14 days — long enough to investigate and replay.

---

## `accounts.tf.json` Contract

```json
"ai-queue": {
  "ai_queue_config_json": {
    "queues": {
      "tasks": {
        "name_suffix": "ai-tasks",
        "type": "standard",
        "visibility_timeout_seconds": 900,
        "message_retention_days": 4,
        "delay_seconds": 0,
        "max_message_size_kb": 256,
        "dlq_enabled": true,
        "dlq_max_receive_count": 3,
        "dlq_retention_days": 14
      },
      "hitl": {
        "name_suffix": "ai-hitl",
        "type": "fifo",
        "visibility_timeout_seconds": 3600,
        "message_retention_days": 14,
        "delay_seconds": 0,
        "max_message_size_kb": 256,
        "dlq_enabled": true,
        "dlq_max_receive_count": 2,
        "dlq_retention_days": 14,
        "content_based_deduplication": true
      }
    }
  }
}
```

**`visibility_timeout_seconds`**: Set to maximum expected task duration.
`ai-tasks` = 900s (15 min, Lambda max). `ai-hitl` = 3600s (1hr, human review window).

**`content_based_deduplication`**: FIFO queue uses content hash for dedup — prevents duplicate
HITL requests if the agent retries the queue send.

---

## Workspace Structure

```
workspaces/ai-queue/
  main.tf      ← SQS queues + DLQs + queue policies
  variables.tf ← ai_queue_config_json (decoded)
  outputs.tf   ← queue URLs, queue ARNs, DLQ ARNs
  data.tf      ← data.tfe_outputs.iam, secure_baseline (KMS)
```

---

## Sample Terraform

### SQS Queues with DLQs

```hcl
locals {
  config = jsondecode(var.ai_queue_config_json)
}

# Dead-letter queues (created first — main queues reference DLQ ARN)
resource "aws_sqs_queue" "dlq" {
  for_each = { for k, q in local.config.queues : k => q if q.dlq_enabled }

  name = "${var.client_id}-${var.env}-${each.value.name_suffix}-dlq${each.value.type == "fifo" ? ".fifo" : ""}"

  message_retention_seconds  = each.value.dlq_retention_days * 86400
  kms_master_key_id          = data.tfe_outputs.secure_baseline.outputs.kms_key_arn

  # FIFO DLQ must also be FIFO
  fifo_queue = each.value.type == "fifo"

  tags = merge(var.tags, {
    Name      = "${var.client_id}-${var.env}-${each.value.name_suffix}-dlq"
    blueprint = "ai-queue"
    queue_type = "dlq"
  })
}

# Main queues
resource "aws_sqs_queue" "queues" {
  for_each = local.config.queues

  name = "${var.client_id}-${var.env}-${each.value.name_suffix}${each.value.type == "fifo" ? ".fifo" : ""}"

  visibility_timeout_seconds  = each.value.visibility_timeout_seconds
  message_retention_seconds   = each.value.message_retention_days * 86400
  delay_seconds               = each.value.delay_seconds
  max_message_size            = each.value.max_message_size_kb * 1024
  kms_master_key_id           = data.tfe_outputs.secure_baseline.outputs.kms_key_arn

  fifo_queue                  = each.value.type == "fifo"
  content_based_deduplication = lookup(each.value, "content_based_deduplication", false)

  # Wire DLQ
  dynamic "redrive_policy" {
    for_each = each.value.dlq_enabled ? [1] : []
    content {
      dead_letter_target_arn = aws_sqs_queue.dlq[each.key].arn
      max_receive_count      = each.value.dlq_max_receive_count
    }
  }

  tags = merge(var.tags, {
    Name       = "${var.client_id}-${var.env}-${each.value.name_suffix}"
    blueprint  = "ai-queue"
    queue_type = each.value.type
  })
}
```

### IAM Policies

```hcl
# Send policy — for API Lambdas submitting tasks to the queue
resource "aws_iam_policy" "queue_send" {
  for_each = local.config.queues

  name        = "${var.client_id}-${var.env}-${each.value.name_suffix}-send"
  description = "Allow sending messages to ${each.value.name_suffix} queue"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
        Resource = aws_sqs_queue.queues[each.key].arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = data.tfe_outputs.secure_baseline.outputs.kms_key_arn
      }
    ]
  })
}

# Receive policy — for worker Lambdas / ECS tasks consuming from the queue
resource "aws_iam_policy" "queue_receive" {
  for_each = local.config.queues

  name        = "${var.client_id}-${var.env}-${each.value.name_suffix}-receive"
  description = "Allow receiving and deleting messages from ${each.value.name_suffix} queue"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = aws_sqs_queue.queues[each.key].arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = data.tfe_outputs.secure_baseline.outputs.kms_key_arn
      }
    ]
  })
}
```

### CloudWatch Alarm — Queue Depth

```hcl
# Alert when tasks pile up (worker not keeping up)
resource "aws_cloudwatch_metric_alarm" "tasks_queue_depth" {
  alarm_name          = "${var.client_id}-${var.env}-ai-tasks-depth-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 100
  alarm_description   = "AI task queue depth > 100 — workers may not be keeping up"

  dimensions = {
    QueueName = aws_sqs_queue.queues["tasks"].name
  }
}

# Alert when tasks hit DLQ (processing failures)
resource "aws_cloudwatch_metric_alarm" "tasks_dlq_depth" {
  alarm_name          = "${var.client_id}-${var.env}-ai-tasks-dlq-nonempty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Messages in AI tasks DLQ — investigate processing failures"

  dimensions = {
    QueueName = aws_sqs_queue.dlq["tasks"].name
  }
}
```

---

## IAM Permissions Required (Bootstrap Role)

```
sqs:CreateQueue
sqs:DeleteQueue
sqs:GetQueueAttributes
sqs:SetQueueAttributes
sqs:TagQueue
iam:CreatePolicy
iam:DeletePolicy
cloudwatch:PutMetricAlarm
cloudwatch:DeleteAlarms
```

---

## Outputs

```hcl
output "tasks_queue_url" {
  description = "SQS standard queue URL for async AI task dispatch"
  value       = aws_sqs_queue.queues["tasks"].url
}

output "tasks_queue_arn" {
  description = "SQS queue ARN — for Lambda event source mapping and IAM policies"
  value       = aws_sqs_queue.queues["tasks"].arn
}

output "hitl_queue_url" {
  description = "SQS FIFO queue URL for human-in-the-loop approval gates"
  value       = aws_sqs_queue.queues["hitl"].url
}

output "hitl_queue_arn" {
  description = "SQS FIFO queue ARN"
  value       = aws_sqs_queue.queues["hitl"].arn
}

output "send_policy_arns" {
  description = "Map of queue key → send IAM policy ARN"
  value       = { for k, p in aws_iam_policy.queue_send : k => p.arn }
}

output "receive_policy_arns" {
  description = "Map of queue key → receive IAM policy ARN"
  value       = { for k, p in aws_iam_policy.queue_receive : k => p.arn }
}
```

---

## Todos

### Infrastructure
- [ ] Create `workspaces/ai-queue/` directory
- [ ] Create `workspaces/ai-queue/main.tf` — queues, DLQs, IAM policies, alarms
- [ ] Create `workspaces/ai-queue/variables.tf` — `ai_queue_config_json` variable
- [ ] Create `workspaces/ai-queue/outputs.tf`
- [ ] Create `workspaces/ai-queue/data.tf` — secure-baseline KMS key, iam outputs

### Control Plane Wiring
- [ ] Add `ai-queue` to `service_working_dirs` map
- [ ] Add dependency: requires `secure-baseline` and `iam` workspaces
- [ ] Add `ai_queue_config_json` validation (valid `type` values: `standard`, `fifo`)

### Consumer Wiring
- [ ] Attach `send_policy_arns.tasks` to API Lambda execution role (for task submission)
- [ ] Attach `receive_policy_arns.tasks` to worker Lambda/ECS task role
- [ ] Configure `tasks_queue_arn` as Lambda event source mapping for worker Lambda
- [ ] Inject `TASKS_QUEUE_URL` and `HITL_QUEUE_URL` as env vars into ECS/Lambda consumers

### Test Client
- [ ] Add `ai-queue` to `test-client-dev` services
- [ ] Apply workspace and verify both queues exist
- [ ] Send test message and confirm DLQ is empty after successful receive+delete

---

## Verification

```bash
# 1. List queues — confirm both exist
aws sqs list-queues --queue-name-prefix "test-client-dev-ai" \
  --query "QueueUrls"
# Expected: 4 URLs (tasks, tasks-dlq, hitl.fifo, hitl-dlq.fifo)

# 2. Send a test message to ai-tasks
TASKS_URL=$(aws sqs get-queue-url \
  --queue-name "test-client-dev-ai-tasks" \
  --query "QueueUrl" --output text)

aws sqs send-message \
  --queue-url "${TASKS_URL}" \
  --message-body '{"task_id":"test-001","type":"ping","tenant_id":"test-tenant"}'
# Expected: MessageId in response

# 3. Receive and delete the test message
RECEIPT=$(aws sqs receive-message \
  --queue-url "${TASKS_URL}" \
  --query "Messages[0].ReceiptHandle" --output text)

aws sqs delete-message \
  --queue-url "${TASKS_URL}" \
  --receipt-handle "${RECEIPT}"
# Expected: no error

# 4. Confirm DLQ is empty
aws sqs get-queue-attributes \
  --queue-url "$(aws sqs get-queue-url --queue-name 'test-client-dev-ai-tasks-dlq' --query QueueUrl --output text)" \
  --attribute-names ApproximateNumberOfMessages \
  --query "Attributes.ApproximateNumberOfMessages"
# Expected: "0"
```

**Gate:** Both queues and both DLQs exist; test message round-trip succeeds; DLQ stays empty.

---

## Cost Notes

| Resource | Cost |
|---|---|
| SQS standard queue | $0.40 per million requests |
| SQS FIFO queue | $0.50 per million requests |
| KMS API calls (SQS encryption) | $0.03 per 10K API calls |
| CloudWatch alarms (2) | $0.20/month |

**At 1K task dispatches/day**: ~$0.01/day.
SQS is effectively free at early-stage volumes.
