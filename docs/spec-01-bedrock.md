# Spec-01: Bedrock Access

**Status:** `[ ] not started`
**Phase:** Wave 1 — Serverless AI Foundations
**Depends on:** `vpc`, `iam`, `secure-baseline` (KMS key)
**Blocks:** `spec-02-ai-gateway`, `spec-06-vector-store` (bedrock-kb backend), `spec-09-ecs`
**Repo(s):** core-tfe-bootstrap-workspace-management

---

## Goal

Provision AWS Bedrock access for a client environment:
- Private model invocation via VPC interface endpoint (no internet egress)
- IAM policies scoped per model family
- Guardrails for content filtering and PII redaction
- Model invocation logging for cost tracking and compliance
- Inference profiles for cross-region resilience

This is the foundation all other AI blueprints depend on for model calls.

---

## Context

AWS Bedrock provides access to foundation models (Claude, Titan, Llama, Nova, Mistral) through
a single API. The `bedrock` blueprint manages the AWS-level access layer — IAM permissions,
network routing, and safety controls. It does not care which AI framework calls it.

Key decisions:
- **VPC endpoint required**: All Bedrock calls route privately. No model invocation traffic
  leaves the client VPC. This is critical for compliance (HIPAA, SOC2) clients.
- **Guardrails per agent type**: Different agent roles (customer-facing, internal, admin) get
  different content policies. Guardrails are named by use case, not by model.
- **Invocation logging**: Model input/output logging is configurable. Default: log metadata
  (model ID, token counts, latency) but NOT input/output content. Clients with audit requirements
  can enable full content logging.
- **Inference profiles**: Cross-region profiles (e.g. `us.anthropic.claude-3-5-sonnet-*`)
  provide automatic failover and capacity benefits. Use these over direct model IDs.

---

## `accounts.tf.json` Contract

```json
"bedrock": {
  "bedrock_config_json": {
    "vpc_endpoint": {
      "enabled": true
    },
    "models": {
      "fast":     "amazon.nova-micro-v1:0",
      "balanced": "anthropic.claude-3-5-sonnet-20241022-v2:0",
      "powerful": "anthropic.claude-opus-4-5"
    },
    "inference_profiles": {
      "balanced": "us.anthropic.claude-3-5-sonnet-20241022-v2:0",
      "powerful": "us.anthropic.claude-opus-4-5"
    },
    "guardrails": {
      "default": {
        "name_suffix": "default",
        "content_filters": ["HATE", "INSULTS", "SEXUAL", "VIOLENCE"],
        "pii_action": "ANONYMIZE",
        "grounding_threshold": "NONE"
      },
      "strict": {
        "name_suffix": "strict",
        "content_filters": ["HATE", "INSULTS", "SEXUAL", "VIOLENCE", "MISCONDUCT"],
        "pii_action": "BLOCK",
        "grounding_threshold": "HIGH"
      }
    },
    "invocation_logging": {
      "enabled": true,
      "retention_days": 90,
      "include_model_input": false,
      "include_model_output": false
    }
  }
}
```

---

## Workspace Structure

```
workspaces/bedrock/
  main.tf          ← VPC endpoint, security group, Guardrails, log group, IAM policy
  variables.tf     ← bedrock_config_json (decoded from TFE variable)
  outputs.tf       ← bedrock_role_arn, guardrail_ids, endpoint_id, inference_profile_arns
  data.tf          ← data.tfe_outputs.vpc, data.tfe_outputs.iam, data.tfe_outputs.secure_baseline
```

---

## Sample Terraform

### VPC Interface Endpoint

```hcl
resource "aws_security_group" "bedrock_endpoint" {
  name        = "${var.client_id}-${var.env}-bedrock-endpoint"
  description = "Allow HTTPS from private subnets to Bedrock VPC endpoint"
  vpc_id      = data.tfe_outputs.vpc.outputs.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = data.tfe_outputs.vpc.outputs.private_subnet_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_endpoint" "bedrock_runtime" {
  vpc_id              = data.tfe_outputs.vpc.outputs.vpc_id
  service_name        = "com.amazonaws.${var.region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.tfe_outputs.vpc.outputs.private_subnet_ids
  security_group_ids  = [aws_security_group.bedrock_endpoint.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.client_id}-${var.env}-bedrock-runtime"
  })
}

# Also provision endpoint for bedrock agent runtime (for Bedrock AgentCore, future)
resource "aws_vpc_endpoint" "bedrock_agent_runtime" {
  vpc_id              = data.tfe_outputs.vpc.outputs.vpc_id
  service_name        = "com.amazonaws.${var.region}.bedrock-agent-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.tfe_outputs.vpc.outputs.private_subnet_ids
  security_group_ids  = [aws_security_group.bedrock_endpoint.id]
  private_dns_enabled = true
}
```

### IAM Policy for Model Invocation

```hcl
locals {
  allowed_model_arns = concat(
    [for tier, model_id in var.config.models :
      "arn:aws:bedrock:${var.region}::foundation-model/${model_id}"],
    [for tier, profile_id in var.config.inference_profiles :
      "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/${profile_id}"]
  )
}

resource "aws_iam_policy" "bedrock_invoke" {
  name        = "${var.client_id}-${var.env}-bedrock-invoke"
  description = "Allow invoking configured Bedrock foundation models and inference profiles"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeModels"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = local.allowed_model_arns
      },
      {
        Sid    = "ApplyGuardrails"
        Effect = "Allow"
        Action = ["bedrock:ApplyGuardrail"]
        Resource = [for k, v in aws_bedrock_guardrail.guardrails :
          "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:guardrail/${v.guardrail_id}"]
      }
    ]
  })
}
```

### Guardrails

```hcl
resource "aws_bedrock_guardrail" "guardrails" {
  for_each = var.config.guardrails

  name                      = "${var.client_id}-${var.env}-${each.value.name_suffix}"
  blocked_input_messaging   = "I'm unable to process that request."
  blocked_outputs_messaging = "I'm unable to provide that response."
  kms_key_arn               = data.tfe_outputs.secure_baseline.outputs.kms_key_arn

  dynamic "content_policy_config" {
    for_each = length(each.value.content_filters) > 0 ? [1] : []
    content {
      dynamic "filters_config" {
        for_each = each.value.content_filters
        content {
          type            = filters_config.value
          input_strength  = "HIGH"
          output_strength = "HIGH"
        }
      }
    }
  }

  sensitive_information_policy_config {
    dynamic "pii_entities_config" {
      for_each = each.value.pii_action != "NONE" ? ["NAME", "EMAIL", "PHONE", "SSN", "CREDIT_DEBIT_CARD_NUMBER"] : []
      content {
        type   = pii_entities_config.value
        action = each.value.pii_action
      }
    }
  }
}
```

### Invocation Logging

```hcl
resource "aws_cloudwatch_log_group" "bedrock_invocations" {
  count             = var.config.invocation_logging.enabled ? 1 : 0
  name              = "/aws/bedrock/${var.client_id}-${var.env}/invocations"
  retention_in_days = var.config.invocation_logging.retention_days
  kms_key_id        = data.tfe_outputs.secure_baseline.outputs.kms_key_arn
}

resource "aws_bedrock_model_invocation_logging_configuration" "this" {
  count = var.config.invocation_logging.enabled ? 1 : 0

  logging_config {
    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.bedrock_invocations[0].name
      role_arn       = aws_iam_role.bedrock_logging.arn
    }
    embedding_data_delivery_enabled  = false
    image_data_delivery_enabled      = false
    text_data_delivery_enabled       = var.config.invocation_logging.include_model_input
  }
}
```

---

## IAM Permissions Required (Bootstrap Role)

```
bedrock:CreateGuardrail
bedrock:DeleteGuardrail
bedrock:GetGuardrail
bedrock:ListGuardrails
bedrock:CreateModelInvocationLoggingConfiguration
bedrock:DeleteModelInvocationLoggingConfiguration
bedrock:GetModelInvocationLoggingConfiguration
bedrock:PutModelInvocationLoggingConfiguration
ec2:CreateVpcEndpoint
ec2:DeleteVpcEndpoint
ec2:DescribeVpcEndpoints
ec2:CreateSecurityGroup
ec2:AuthorizeSecurityGroupIngress
ec2:AuthorizeSecurityGroupEgress
iam:CreatePolicy
iam:CreateRole
iam:AttachRolePolicy
logs:CreateLogGroup
logs:PutRetentionPolicy
```

---

## Outputs

```hcl
output "bedrock_invoke_policy_arn" {
  description = "IAM policy ARN — attach to any role that needs model invocation"
  value       = aws_iam_policy.bedrock_invoke.arn
}

output "guardrail_ids" {
  description = "Map of guardrail name → guardrail ID"
  value       = { for k, v in aws_bedrock_guardrail.guardrails : k => v.guardrail_id }
}

output "guardrail_arns" {
  description = "Map of guardrail name → guardrail ARN (for Bedrock API calls)"
  value       = { for k, v in aws_bedrock_guardrail.guardrails : k => v.guardrail_arn }
}

output "bedrock_endpoint_id" {
  description = "VPC endpoint ID for Bedrock runtime"
  value       = aws_vpc_endpoint.bedrock_runtime.id
}

output "invocation_log_group_name" {
  description = "CloudWatch log group for Bedrock model invocation logs"
  value       = var.config.invocation_logging.enabled ? aws_cloudwatch_log_group.bedrock_invocations[0].name : null
}
```

---

## Todos

### Infrastructure
- [ ] Create `workspaces/bedrock/` directory
- [ ] Create `workspaces/bedrock/main.tf` — VPC endpoint, security group, Guardrails
- [ ] Create `workspaces/bedrock/variables.tf` — `bedrock_config_json` variable (string, decoded with `jsondecode`)
- [ ] Create `workspaces/bedrock/outputs.tf` — all outputs listed above
- [ ] Create `workspaces/bedrock/data.tf` — `data.tfe_outputs.vpc`, `.iam`, `.secure_baseline`
- [ ] Create `modules/aws/bedrock-access/` — reusable module wrapping the above

### Control Plane Wiring
- [ ] Add `bedrock` to `service_working_dirs` map in `bootstrap-accounts/` module
- [ ] Add `bedrock` dependency rules: requires `vpc` and `iam` workspaces to exist
- [ ] Add `bedrock` as a valid service name in `accounts.tf.json` validation `precondition`
- [ ] Add `service_workspace_variables.bedrock.bedrock_config_json` schema validation

### Test Client
- [ ] Add `bedrock` to `bootstrap-accounts-dev/accounts.tf.json` for `test-client-dev`
- [ ] Populate `bedrock_config_json` with one guardrail and invocation logging enabled
- [ ] Apply `test-client-dev-bedrock` workspace and verify outputs

---

## Verification

```bash
# 1. Confirm VPC endpoint is available
aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.us-east-1.bedrock-runtime" \
            "Name=tag:client_id,Values=test-client" \
  --query "VpcEndpoints[0].State"
# Expected: "available"

# 2. Confirm guardrail exists
aws bedrock list-guardrails \
  --query "guardrails[?name=='test-client-dev-default'].guardrailId"
# Expected: ["<guardrail-id>"]

# 3. Test model invocation (from within the VPC, e.g., a bastion Lambda)
aws bedrock-runtime invoke-model \
  --model-id amazon.nova-micro-v1:0 \
  --body '{"messages":[{"role":"user","content":[{"type":"text","text":"ping"}]}],"inferenceConfig":{"maxTokens":10}}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/response.json && cat /tmp/response.json
# Expected: response with completion text

# 4. Confirm invocation log entry appears (if logging enabled)
aws logs tail /aws/bedrock/test-client-dev/invocations --since 5m
```

**Gate:** VPC endpoint in `available` state + guardrail created + model invocation succeeds
before `spec-02` (ai-gateway) can be applied.

---

## Cost Notes

| Resource | Cost |
|---|---|
| VPC interface endpoint (bedrock-runtime) | ~$7.30/month (1 AZ) + $0.01/GB data processed |
| VPC interface endpoint (bedrock-agent-runtime) | ~$7.30/month (1 AZ) |
| Bedrock Guardrails | $0 to create; charged per guardrail unit when applied (~$0.75/1K text units) |
| Invocation logging (CloudWatch) | ~$0.50/GB ingested |
| **Model calls** | Variable — charged per input/output token per model |

Total infrastructure cost (excluding model calls): **~$15-20/month**

Bedrock model pricing reference (us-east-1, 2026-05):
- Nova Micro (fast): $0.000035/1K input tokens, $0.00014/1K output tokens
- Claude 3.5 Sonnet (balanced): $0.003/1K input, $0.015/1K output
- Claude Opus (powerful): $0.015/1K input, $0.075/1K output
