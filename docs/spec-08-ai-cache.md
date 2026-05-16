# Spec-08: AI Cache

**Status:** `[ ] not started`
**Phase:** Wave 3 — Caching
**Depends on:** `vpc`, `iam`, `secure-baseline` (KMS key)
**Blocks:** nothing (optional enhancement — improves cost and latency)
**Repo(s):** core-tfe-bootstrap-workspace-management

---

## Goal

Provision ElastiCache Serverless Redis for:
1. **LLM response caching** — skip redundant model calls for identical/similar inputs (semantic cache)
2. **Session state** — fast ephemeral key-value store for active agent sessions
3. **Per-tenant rate limit counters** — sliding window counters enforced at the gateway
4. **Tool result caching** — cache expensive tool call results (API lookups, DB queries)

---

## Context

A single Claude 3.5 Sonnet call costs ~$0.003-0.015 per request. At scale, many requests ask
semantically identical questions. Response caching can reduce model call costs by 30-60%.

**Serverless Redis**: ElastiCache Serverless auto-scales with zero minimum commitment.
No cluster sizing decisions. Pay for data stored and compute units consumed. At zero traffic: ~$0.

The cache is advisory — AI frameworks gracefully degrade if Redis is unreachable.
No AI functionality breaks if the cache is cold or unavailable.

**Semantic caching (application-level)**: The AI gateway (LiteLLM) supports Redis-backed
semantic caching. When enabled:
1. Incoming request is embedded
2. Embedding is looked up against cached embeddings (cosine similarity)
3. If similarity > threshold → return cached response (no model call)
4. If no match → call model → cache response + embedding

This is configured in LiteLLM's `config.yaml`, not in Terraform. The Terraform blueprint
provisions the Redis endpoint and injects it as an env var into the gateway.

---

## `accounts.tf.json` Contract

```json
"ai-cache": {
  "ai_cache_config_json": {
    "type": "serverless",
    "max_storage_gb": 5,
    "max_ecpu_per_second": 1000,
    "tls_enabled": true,
    "multi_az": false,
    "snapshot_enabled": false,
    "log_delivery_enabled": false
  }
}
```

**`max_storage_gb`**: Soft limit on maximum storage. ElastiCache Serverless will not hard-stop
at this limit but billing continues. Set to an amount that would trigger a cost alarm.

**`max_ecpu_per_second`**: ElastiCache Compute Units (eCPU) cap. 1000 eCPU ≈ handling ~1K
simple operations/second. Increase when response cache hit rate is high enough to justify it.

**`multi_az`**: Set `false` for dev/workbench. Set `true` for production (automatic failover).

---

## Workspace Structure

```
workspaces/ai-cache/
  main.tf      ← ElastiCache Serverless cluster, security group, subnet group
  variables.tf ← ai_cache_config_json (decoded)
  outputs.tf   ← endpoint_address, endpoint_port, auth_token_secret_arn
  data.tf      ← vpc outputs, secure_baseline (KMS)
```

---

## Sample Terraform

### ElastiCache Serverless Cluster

```hcl
locals {
  config = jsondecode(var.ai_cache_config_json)
}

resource "aws_security_group" "ai_cache" {
  name        = "${var.client_id}-${var.env}-ai-cache"
  description = "Allow Redis access from AI services"
  vpc_id      = data.tfe_outputs.vpc.outputs.vpc_id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = data.tfe_outputs.vpc.outputs.private_subnet_cidrs
    description = "Redis from private subnets"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.client_id}-${var.env}-ai-cache" })
}

resource "aws_elasticache_serverless_cache" "ai_cache" {
  engine = "redis"
  name   = "${var.client_id}-${var.env}-ai-cache"

  cache_usage_limits {
    data_storage {
      maximum = local.config.max_storage_gb
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = local.config.max_ecpu_per_second
    }
  }

  kms_key_id = data.tfe_outputs.secure_baseline.outputs.kms_key_arn

  security_group_ids = [aws_security_group.ai_cache.id]
  subnet_ids         = data.tfe_outputs.vpc.outputs.private_subnet_ids

  # TLS — all Redis traffic encrypted in transit
  # ElastiCache Serverless enforces TLS by default (cannot disable)

  # Multi-AZ (production)
  major_engine_version = "7"

  tags = merge(var.tags, {
    Name      = "${var.client_id}-${var.env}-ai-cache"
    blueprint = "ai-cache"
  })
}
```

### IAM Policy for Redis Access

```hcl
# ElastiCache Serverless uses IAM auth (via IRSA or task role)
resource "aws_iam_policy" "cache_connect" {
  name        = "${var.client_id}-${var.env}-ai-cache-connect"
  description = "Allow connection to AI cache via IAM auth"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ConnectCache"
        Effect = "Allow"
        Action = ["elasticache:Connect"]
        Resource = [
          aws_elasticache_serverless_cache.ai_cache.arn,
          "arn:aws:elasticache:${var.region}:${data.aws_caller_identity.current.account_id}:user:*"
        ]
      },
      {
        Sid    = "KmsDecrypt"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = [data.tfe_outputs.secure_baseline.outputs.kms_key_arn]
      }
    ]
  })
}
```

### CloudWatch Alarms

```hcl
# Alert when cache is near storage limit
resource "aws_cloudwatch_metric_alarm" "cache_storage_high" {
  alarm_name          = "${var.client_id}-${var.env}-ai-cache-storage-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BytesUsedForCache"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Maximum"
  threshold           = local.config.max_storage_gb * 1073741824 * 0.8  # 80% of max
  alarm_description   = "AI cache storage > 80% of configured limit"

  dimensions = {
    CacheName = aws_elasticache_serverless_cache.ai_cache.name
  }
}
```

### How AI Gateway Connects (LiteLLM Config Snippet)

```yaml
# In LiteLLM config.yaml (rendered by spec-02-ai-gateway Terraform template)
# This is application config, not Terraform — included here for context

litellm_settings:
  cache: true
  cache_params:
    type: redis
    host: "${REDIS_ENDPOINT}"      # injected from Terraform output
    port: 6379
    ssl: true
    ssl_cert_reqs: required
    similarity_threshold: 0.8      # semantic similarity cutoff for cache hits
    supported_call_types:
      - acompletion
      - completion
```

---

## IAM Permissions Required (Bootstrap Role)

```
elasticache:CreateServerlessCache
elasticache:DeleteServerlessCache
elasticache:DescribeServerlessCaches
elasticache:ModifyServerlessCache
ec2:CreateSecurityGroup
ec2:AuthorizeSecurityGroupIngress
ec2:AuthorizeSecurityGroupEgress
iam:CreatePolicy
iam:DeletePolicy
cloudwatch:PutMetricAlarm
cloudwatch:DeleteAlarms
```

---

## Outputs

```hcl
output "endpoint_address" {
  description = "Redis endpoint address — inject as REDIS_ENDPOINT env var"
  value       = aws_elasticache_serverless_cache.ai_cache.endpoint[0].address
}

output "endpoint_port" {
  description = "Redis port (always 6379)"
  value       = 6379
}

output "cache_arn" {
  description = "ElastiCache Serverless cache ARN"
  value       = aws_elasticache_serverless_cache.ai_cache.arn
}

output "connect_policy_arn" {
  description = "IAM policy ARN for cache connection — attach to ECS task role and Lambda execution role"
  value       = aws_iam_policy.cache_connect.arn
}
```

---

## Todos

### Infrastructure
- [ ] Create `workspaces/ai-cache/` directory
- [ ] Create `workspaces/ai-cache/main.tf` — serverless cluster, security group, alarm
- [ ] Create `workspaces/ai-cache/variables.tf` — `ai_cache_config_json` variable
- [ ] Create `workspaces/ai-cache/outputs.tf`
- [ ] Create `workspaces/ai-cache/data.tf` — vpc, secure_baseline outputs

### Control Plane Wiring
- [ ] Add `ai-cache` to `service_working_dirs` map
- [ ] Add dependency: requires `vpc`, `secure-baseline`, `iam`
- [ ] Inject `endpoint_address` into `ai-gateway` workspace as `REDIS_ENDPOINT` env var

### Consumer Wiring
- [ ] Attach `connect_policy_arn` to ECS task role and Lambda execution role
- [ ] Inject `REDIS_ENDPOINT` into ai-gateway and ECS task environment variables

### Test Client
- [ ] Add `ai-cache` to `test-client-dev` services
- [ ] Apply and verify cache is in `available` state
- [ ] Test Redis connection from a Lambda in the same VPC

---

## Verification

```bash
# 1. Confirm cache is available
aws elasticache describe-serverless-caches \
  --serverless-cache-name "test-client-dev-ai-cache" \
  --query "ServerlessCaches[0].Status"
# Expected: "available"

# 2. Confirm endpoint is reachable from within the VPC
# (Run from a Lambda or ECS task in the same VPC)
redis-cli -h $(terraform output -raw endpoint_address) -p 6379 --tls PING
# Expected: PONG

# 3. Test set/get
redis-cli -h $(terraform output -raw endpoint_address) -p 6379 --tls \
  SET test:key "hello" EX 60
redis-cli -h $(terraform output -raw endpoint_address) -p 6379 --tls \
  GET test:key
# Expected: "hello"
```

**Gate:** Cache in `available` state; PING/PONG succeeds from within VPC; SET/GET round-trip works.

---

## Cost Notes

| Resource | Cost |
|---|---|
| ElastiCache Serverless (data storage) | $0.125/GB/hour |
| ElastiCache Serverless (eCPU) | $0.0034/eCPU-hour |
| Data transfer (within VPC) | Free |
| CloudWatch alarm | $0.10/month |

**At idle with no data**: ~$0/month (serverless, no minimum).
**At 1GB cached data, 100 eCPU/s**: ~$3-5/month.

Expected savings: If semantic caching eliminates 30% of model calls at $0.005/call average:
100 calls/day × 0.30 × $0.005 × 30 = ~$4.50/month savings vs ~$3-5/month cache cost.
Break-even at ~200 calls/day.
