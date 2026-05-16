# Spec-10: AI Observability

**Status:** `[ ] not started`
**Phase:** Wave 4 — Observability (after all prior blueprints)
**Depends on:** `iam`, `secure-baseline` (KMS key), `spec-01-bedrock` (invocation logs), optionally all other AI blueprints
**Blocks:** nothing (enhances visibility but not a hard dependency)
**Repo(s):** core-tfe-bootstrap-workspace-management

---

## Goal

Provision purpose-built observability infrastructure for AI workloads. Standard CloudWatch
covers infrastructure metrics (CPU, memory, errors). AI observability adds:

- **Token usage** — by model tier, by tenant, by day
- **Cost per request** — model costs tracked in real time
- **Model latency p99** — where time is being spent
- **Resolution rate** — what % of agent tasks complete without human escalation
- **RAG retrieval quality** — average retrieval score per collection
- **Error breakdown** — model errors vs tool errors vs orchestration errors
- **HITL gate frequency** — how often agents escalate to humans

These metrics are emitted by the AI services (forge-core-ai) to CloudWatch. This blueprint
creates the receiving infrastructure: log groups, dashboards, alarms, and X-Ray groups.

---

## Context

**Why a dedicated blueprint?** Observability config for AI is different from standard infra
observability. Token budgets, cost alarms, and resolution rate are not standard CloudWatch
metrics. They require custom metric namespaces, structured log patterns, and domain-specific
alarm thresholds.

**Who emits metrics?** The AI services (ECS tasks, Lambda functions) emit metrics using
the AWS SDK CloudWatch Embedded Metric Format (EMF). EMF lets services emit structured logs
that CloudWatch automatically converts to custom metrics — no `put-metric-data` API call needed.

```python
# Example: forge-core-ai emitting AI metrics via EMF
from aws_embedded_metrics import metric_scope

@metric_scope
async def handle_chat(event, metrics):
    result = await agent.run(event["message"])
    metrics.put_metric("TokensConsumed", result.token_count, "Count")
    metrics.put_metric("ModelLatencyMs", result.latency_ms, "Milliseconds")
    metrics.put_metric("CostUSD", result.cost_usd, "None")
    metrics.set_property("ModelTier", result.model_tier)
    metrics.set_property("TenantId", event["tenant_id"])
    return result
```

**Framework-agnostic**: This blueprint creates the log groups and metric namespace.
Any AI framework can emit to this namespace using EMF or standard CloudWatch SDK calls.

---

## `accounts.tf.json` Contract

```json
"ai-obs": {
  "ai_obs_config_json": {
    "metric_namespace": "AgentForge/AI",
    "log_retention_days": 30,
    "dashboards": {
      "cost": { "enabled": true },
      "latency": { "enabled": true },
      "quality": { "enabled": true }
    },
    "alarms": {
      "token_budget": {
        "daily_token_limit": 10000000,
        "alert_at_percentage": 80
      },
      "cost_anomaly": {
        "daily_cost_threshold_usd": 50
      },
      "latency_p99": {
        "threshold_ms": 10000,
        "evaluation_periods": 3
      },
      "error_rate": {
        "threshold_percentage": 5,
        "evaluation_periods": 2
      },
      "hitl_frequency": {
        "threshold_per_hour": 20
      }
    },
    "xray": {
      "enabled": true,
      "sampling_rate": 0.05
    }
  }
}
```

---

## Workspace Structure

```
workspaces/ai-obs/
  main.tf          ← Log groups, metric filters, dashboards, alarms
  xray.tf          ← X-Ray group + sampling rule
  variables.tf     ← ai_obs_config_json (decoded)
  outputs.tf       ← log group names, dashboard names, alarm ARNs
  data.tf          ← iam, secure_baseline, bedrock (invocation log group)
```

---

## Sample Terraform

### Log Groups

```hcl
locals {
  config = jsondecode(var.ai_obs_config_json)

  log_groups = {
    ai_gateway   = "/ai/${var.client_id}-${var.env}/gateway"
    ai_engine    = "/ai/${var.client_id}-${var.env}/engine"
    ai_worker    = "/ai/${var.client_id}-${var.env}/worker"
    agent_state  = "/ai/${var.client_id}-${var.env}/agent-state"
    hitl         = "/ai/${var.client_id}-${var.env}/hitl"
    rag          = "/ai/${var.client_id}-${var.env}/rag"
  }
}

resource "aws_cloudwatch_log_group" "ai" {
  for_each = local.log_groups

  name              = each.value
  retention_in_days = local.config.log_retention_days
  kms_key_id        = data.tfe_outputs.secure_baseline.outputs.kms_key_arn

  tags = merge(var.tags, {
    blueprint = "ai-obs"
    component = each.key
  })
}
```

### Custom Metric Filters (EMF → Metrics)

```hcl
# Token usage filter — extracts TokensConsumed from EMF logs
resource "aws_cloudwatch_log_metric_filter" "tokens_consumed" {
  name           = "${var.client_id}-${var.env}-tokens-consumed"
  pattern        = "{ $.TokensConsumed > 0 }"
  log_group_name = aws_cloudwatch_log_group.ai["ai_engine"].name

  metric_transformation {
    name          = "TokensConsumed"
    namespace     = "${local.config.metric_namespace}/${var.client_id}"
    value         = "$.TokensConsumed"
    unit          = "Count"
    default_value = "0"
    dimensions = {
      ModelTier = "$.ModelTier"
      TenantId  = "$.TenantId"
    }
  }
}

# Model latency filter
resource "aws_cloudwatch_log_metric_filter" "model_latency" {
  name           = "${var.client_id}-${var.env}-model-latency"
  pattern        = "{ $.ModelLatencyMs > 0 }"
  log_group_name = aws_cloudwatch_log_group.ai["ai_engine"].name

  metric_transformation {
    name      = "ModelLatencyMs"
    namespace = "${local.config.metric_namespace}/${var.client_id}"
    value     = "$.ModelLatencyMs"
    unit      = "Milliseconds"
    dimensions = {
      ModelTier = "$.ModelTier"
    }
  }
}

# Cost filter
resource "aws_cloudwatch_log_metric_filter" "cost_usd" {
  name           = "${var.client_id}-${var.env}-cost-usd"
  pattern        = "{ $.CostUSD > 0 }"
  log_group_name = aws_cloudwatch_log_group.ai["ai_engine"].name

  metric_transformation {
    name      = "CostUSD"
    namespace = "${local.config.metric_namespace}/${var.client_id}"
    value     = "$.CostUSD"
    unit      = "None"
    dimensions = {
      ModelTier = "$.ModelTier"
      TenantId  = "$.TenantId"
    }
  }
}

# HITL escalation filter
resource "aws_cloudwatch_log_metric_filter" "hitl_escalations" {
  name           = "${var.client_id}-${var.env}-hitl-escalations"
  pattern        = "{ $.EventType = \"HITL_ESCALATION\" }"
  log_group_name = aws_cloudwatch_log_group.ai["hitl"].name

  metric_transformation {
    name      = "HITLEscalations"
    namespace = "${local.config.metric_namespace}/${var.client_id}"
    value     = "1"
    unit      = "Count"
  }
}
```

### CloudWatch Alarms

```hcl
# Daily token budget alarm
resource "aws_cloudwatch_metric_alarm" "token_budget" {
  alarm_name          = "${var.client_id}-${var.env}-ai-token-budget-80pct"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TokensConsumed"
  namespace           = "${local.config.metric_namespace}/${var.client_id}"
  period              = 86400  # 1 day
  statistic           = "Sum"
  threshold           = local.config.alarms.token_budget.daily_token_limit * (local.config.alarms.token_budget.alert_at_percentage / 100)
  alarm_description   = "Daily token consumption > ${local.config.alarms.token_budget.alert_at_percentage}% of budget"
  treat_missing_data  = "notBreaching"
}

# p99 latency alarm
resource "aws_cloudwatch_metric_alarm" "latency_p99" {
  alarm_name          = "${var.client_id}-${var.env}-ai-latency-p99-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = local.config.alarms.latency_p99.evaluation_periods
  extended_statistic  = "p99"
  metric_name         = "ModelLatencyMs"
  namespace           = "${local.config.metric_namespace}/${var.client_id}"
  period              = 300
  threshold           = local.config.alarms.latency_p99.threshold_ms
  alarm_description   = "Model latency p99 > ${local.config.alarms.latency_p99.threshold_ms}ms"
  treat_missing_data  = "notBreaching"
}

# Cost anomaly alarm — daily spend spike
resource "aws_cloudwatch_metric_alarm" "daily_cost" {
  alarm_name          = "${var.client_id}-${var.env}-ai-daily-cost-spike"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CostUSD"
  namespace           = "${local.config.metric_namespace}/${var.client_id}"
  period              = 86400
  statistic           = "Sum"
  threshold           = local.config.alarms.cost_anomaly.daily_cost_threshold_usd
  alarm_description   = "Daily AI model cost > $${local.config.alarms.cost_anomaly.daily_cost_threshold_usd}"
  treat_missing_data  = "notBreaching"
}

# HITL frequency alarm
resource "aws_cloudwatch_metric_alarm" "hitl_frequency" {
  alarm_name          = "${var.client_id}-${var.env}-ai-hitl-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HITLEscalations"
  namespace           = "${local.config.metric_namespace}/${var.client_id}"
  period              = 3600
  statistic           = "Sum"
  threshold           = local.config.alarms.hitl_frequency.threshold_per_hour
  alarm_description   = "HITL escalations > ${local.config.alarms.hitl_frequency.threshold_per_hour}/hour — agent confidence may be low"
  treat_missing_data  = "notBreaching"
}
```

### CloudWatch Dashboards

```hcl
resource "aws_cloudwatch_dashboard" "cost" {
  count          = local.config.dashboards.cost.enabled ? 1 : 0
  dashboard_name = "${var.client_id}-${var.env}-ai-cost"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title   = "Daily AI Cost (USD)"
          metrics = [[
            "${local.config.metric_namespace}/${var.client_id}",
            "CostUSD",
            { stat = "Sum", period = 86400, label = "Total Cost" }
          ]]
          view    = "timeSeries"
          period  = 86400
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title   = "Tokens Consumed by Tier"
          metrics = [
            ["${local.config.metric_namespace}/${var.client_id}", "TokensConsumed", "ModelTier", "fast",     { label = "Fast (Nova Micro)" }],
            ["${local.config.metric_namespace}/${var.client_id}", "TokensConsumed", "ModelTier", "balanced", { label = "Balanced (Sonnet)" }],
            ["${local.config.metric_namespace}/${var.client_id}", "TokensConsumed", "ModelTier", "powerful", { label = "Powerful (Opus)" }]
          ]
          view   = "timeSeries"
          period = 3600
        }
      }
    ]
  })
}

resource "aws_cloudwatch_dashboard" "latency" {
  count          = local.config.dashboards.latency.enabled ? 1 : 0
  dashboard_name = "${var.client_id}-${var.env}-ai-latency"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 24
        height = 6
        properties = {
          title   = "Model Latency (p50 / p99)"
          metrics = [
            ["${local.config.metric_namespace}/${var.client_id}", "ModelLatencyMs", { stat = "p50",  label = "p50" }],
            ["${local.config.metric_namespace}/${var.client_id}", "ModelLatencyMs", { stat = "p99",  label = "p99" }],
            ["${local.config.metric_namespace}/${var.client_id}", "ModelLatencyMs", { stat = "p999", label = "p999" }]
          ]
          view   = "timeSeries"
          period = 300
        }
      }
    ]
  })
}
```

### X-Ray

```hcl
resource "aws_xray_group" "ai" {
  count      = local.config.xray.enabled ? 1 : 0
  group_name = "${var.client_id}-${var.env}-ai"

  filter_expression = "service(\"${var.client_id}-${var.env}-ai-engine\") OR service(\"${var.client_id}-${var.env}-ai-gateway\")"

  insights_configuration {
    insights_enabled      = true
    notifications_enabled = true
  }
}

resource "aws_xray_sampling_rule" "ai" {
  count       = local.config.xray.enabled ? 1 : 0
  rule_name   = "${var.client_id}-${var.env}-ai"
  priority    = 100
  reservoir_size = 5
  fixed_rate  = local.config.xray.sampling_rate
  url_path    = "*"
  host        = "*"
  http_method = "*"
  service_type = "*"
  service_name = "${var.client_id}-${var.env}-ai-*"
  resource_arn = "*"
  version     = 1
}
```

---

## IAM Permissions Required (Bootstrap Role)

```
cloudwatch:PutDashboard, cloudwatch:DeleteDashboards
cloudwatch:PutMetricAlarm, cloudwatch:DeleteAlarms
logs:CreateLogGroup, logs:DeleteLogGroup
logs:PutRetentionPolicy, logs:PutMetricFilter, logs:DeleteMetricFilter
xray:CreateGroup, xray:DeleteGroup
xray:CreateSamplingRule, xray:UpdateSamplingRule, xray:DeleteSamplingRule
```

---

## Outputs

```hcl
output "log_group_names" {
  description = "Map of component → log group name — inject as env vars into AI services"
  value       = { for k, lg in aws_cloudwatch_log_group.ai : k => lg.name }
}

output "metric_namespace" {
  description = "CloudWatch custom metric namespace — AI services emit here"
  value       = "${local.config.metric_namespace}/${var.client_id}"
}

output "alarm_arns" {
  description = "Map of alarm name → alarm ARN — for SNS notification wiring"
  value = {
    token_budget   = aws_cloudwatch_metric_alarm.token_budget.arn
    latency_p99    = aws_cloudwatch_metric_alarm.latency_p99.arn
    daily_cost     = aws_cloudwatch_metric_alarm.daily_cost.arn
    hitl_frequency = aws_cloudwatch_metric_alarm.hitl_frequency.arn
  }
}

output "xray_group_arn" {
  description = "X-Ray group ARN for AI services"
  value       = local.config.xray.enabled ? aws_xray_group.ai[0].arn : null
}
```

---

## Todos

### Infrastructure
- [ ] Create `workspaces/ai-obs/main.tf` — log groups, metric filters, alarms, dashboards
- [ ] Create `workspaces/ai-obs/xray.tf` — X-Ray group and sampling rule
- [ ] Create `workspaces/ai-obs/variables.tf` — `ai_obs_config_json` variable
- [ ] Create `workspaces/ai-obs/outputs.tf`
- [ ] Create `workspaces/ai-obs/data.tf` — iam, secure_baseline outputs

### Control Plane Wiring
- [ ] Add `ai-obs` to `service_working_dirs` map
- [ ] Add dependency: requires `secure-baseline` (KMS for log groups)
- [ ] Expose `log_group_names` output — inject into ECS task definitions and Lambda env vars
- [ ] Expose `metric_namespace` output — configure in AI service startup

### AI Services Integration (forge-core-ai)
- [ ] Add `aws-embedded-metrics` Python package to forge-core-ai
- [ ] Emit `TokensConsumed`, `ModelLatencyMs`, `CostUSD` from LLM call wrapper
- [ ] Emit `HITLEscalations` from HITL gate handler
- [ ] Set `AWS_EMF_LOG_GROUP` env var to `log_group_names.ai_engine` output value

### Test Client
- [ ] Add `ai-obs` to `test-client-dev` services
- [ ] Apply and verify all log groups, alarms, and dashboards created
- [ ] Emit a test metric and confirm it appears in CloudWatch custom metrics

---

## Verification

```bash
# 1. List AI log groups
aws logs describe-log-groups \
  --log-group-name-prefix "/ai/test-client-dev" \
  --query "logGroups[*].logGroupName"
# Expected: 6 log group names

# 2. List alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix "test-client-dev-ai" \
  --query "MetricAlarms[*].{name:AlarmName,state:StateValue}"
# Expected: 4 alarms in OK or INSUFFICIENT_DATA state

# 3. List dashboards
aws cloudwatch list-dashboards \
  --dashboard-name-prefix "test-client-dev-ai" \
  --query "DashboardEntries[*].DashboardName"
# Expected: ["test-client-dev-ai-cost", "test-client-dev-ai-latency", "test-client-dev-ai-quality"]

# 4. Test custom metric emission
aws cloudwatch put-metric-data \
  --namespace "AgentForge/AI/test-client" \
  --metric-name "TokensConsumed" \
  --value 1000 \
  --dimensions ModelTier=balanced,TenantId=test-tenant \
  --unit Count

aws cloudwatch get-metric-statistics \
  --namespace "AgentForge/AI/test-client" \
  --metric-name "TokensConsumed" \
  --dimensions Name=ModelTier,Value=balanced \
  --start-time $(date -u -v-5M +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --query "Datapoints[0].Sum"
# Expected: 1000.0

# 5. Confirm X-Ray sampling rule
aws xray get-sampling-rules \
  --query "SamplingRuleRecords[?SamplingRule.RuleName=='test-client-dev-ai'].SamplingRule.FixedRate"
# Expected: 0.05
```

**Gate:** Log groups created; alarms in INSUFFICIENT_DATA or OK state; test metric appears
in CloudWatch custom metrics within 5 minutes of emission.

---

## Cost Notes

| Resource | Cost |
|---|---|
| CloudWatch log ingestion | $0.50/GB |
| CloudWatch log storage | $0.03/GB/month |
| CloudWatch metric filter | $0 |
| CloudWatch custom metric | $0.30/metric/month (first 10K free) |
| CloudWatch alarms (4) | $0.10/alarm/month = $0.40/month |
| CloudWatch dashboard (3) | $3.00/dashboard/month = $9/month |
| X-Ray traces | $5.00 per million traces recorded; first 100K free/month |
| X-Ray trace storage | $0.50/million trace segments stored |

**At low volume**: ~$10-12/month (dashboards are the dominant cost at $3 each).
Dashboards can be disabled via config if cost is a concern.

At high volume, CloudWatch log ingestion becomes significant:
- 1GB/day × $0.50 = $15/month — use structured logging and appropriate log retention.
