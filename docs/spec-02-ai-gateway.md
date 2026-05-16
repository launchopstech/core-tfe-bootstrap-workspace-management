# Spec-02: AI Gateway

**Status:** `[ ] not started`
**Phase:** Wave 2 — Model Access
**Depends on:** `spec-01-bedrock`, `secrets`, `iam`, `spec-07-ecr` (image storage)
**Blocks:** All AI framework deployments (any service calling models goes through here)
**Repo(s):** core-tfe-bootstrap-workspace-management

---

## Goal

Deploy a single internal AI model gateway that:
- Routes model calls to the right provider by tier (`fast` / `balanced` / `powerful`)
- Is serverless-first (Lambda) with a clear migration path to ECS when scale demands it
- Exposes an OpenAI-compatible API endpoint — any framework connects without provider code changes
- Supports multi-provider routing: Bedrock primary, Anthropic direct as fallback

**The AI framework never calls Bedrock or Anthropic APIs directly.** It calls this gateway.
Changing the model provider = update gateway config. Zero framework change.

---

## Context

### Why a Gateway?

Without a gateway, every AI service embeds provider-specific config: API keys, endpoint URLs,
model IDs, retry logic, rate limits. This creates:
- Provider lock-in at the framework level
- Duplicated rate limiting per service
- No central cost attribution
- Secret sprawl (each service holds its own API keys)

The gateway centralises all of this. AI services call one internal URL.

### Serverless-First Evolution

```
Phase A (Launch → first scale milestone):
  Lambda function with LiteLLM embedded
  → Lambda Function URL (IAM auth)
  → $0 idle cost
  → Cold start: ~2-3s (acceptable for non-streaming)
  → Limit: 15-min timeout, 10GB memory, 1000 concurrent invocations

Phase B (scale trigger: >500 req/day or streaming latency complaints):
  ECS Fargate service running LiteLLM container
  → Persistent warm connection to Bedrock
  → Streaming SSE supported natively
  → $30-50/month always-on

Alternative (evaluate post-launch):
  AWS Bedrock AgentCore
  → Fully managed serverless agent runtime
  → Built-in: memory, tools, knowledge retrieval, observability
  → Replaces ai-gateway + agent-state + ai-obs for simple workflows
  → Evaluate when Bedrock AgentCore GA and pricing is stable
```

### LiteLLM as the Proxy

LiteLLM provides an OpenAI-compatible proxy that routes to 100+ providers via a unified API.
It is configured via YAML and supports:
- Model aliasing (`fast`, `balanced`, `powerful` → actual model IDs)
- Per-provider rate limits and retries
- Cost tracking and budget limits
- Redis caching integration

LiteLLM is a **configuration choice**, not an infrastructure requirement. If a better proxy
emerges (e.g., native Bedrock routing, OpenRouter), the Lambda container image is swapped.
The Terraform blueprint stays identical.

---

## `accounts.tf.json` Contract

```json
"ai-gateway": {
  "ai_gateway_config_json": {
    "runtime": "lambda",
    "image_tag": "latest",
    "memory_mb": 1024,
    "timeout_seconds": 300,
    "providers": {
      "bedrock": {
        "enabled": true,
        "region": "us-east-1"
      },
      "anthropic": {
        "enabled": true,
        "api_key_secret_ref": "anthropic_api_key"
      },
      "openai": {
        "enabled": false,
        "api_key_secret_ref": ""
      }
    },
    "model_tiers": {
      "fast":     "bedrock/amazon.nova-micro-v1:0",
      "balanced": "bedrock/us.anthropic.claude-3-5-sonnet-20241022-v2:0",
      "powerful": "bedrock/us.anthropic.claude-opus-4-5",
      "fallback": "anthropic/claude-3-5-sonnet-20241022"
    },
    "rate_limits": {
      "requests_per_minute": 60,
      "tokens_per_minute": 100000
    },
    "cache": {
      "enabled": false,
      "redis_ref": ""
    }
  }
}
```

**`runtime`**: `"lambda"` (Phase A) or `"ecs"` (Phase B). Changing this triggers a different
Terraform resource path — Lambda function URL vs ECS service with load balancer.

**`model_tiers`**: Maps logical tier names to `provider/model-id`. Frameworks call the tier name,
never a model ID directly.

---

## Workspace Structure

```
workspaces/ai-gateway/
  main.tf          ← Lambda function (Phase A) or ECS service (Phase B)
  variables.tf     ← ai_gateway_config_json (decoded), plus vpc/bedrock/secrets inputs
  outputs.tf       ← endpoint_url, function_arn (Phase A) or service_arn (Phase B)
  litellm_config/
    config.yaml.tpl  ← LiteLLM config template, rendered from Terraform locals
  data.tf          ← data.tfe_outputs.bedrock, .secrets, .iam, .vpc (Phase B only)
```

---

## Sample Terraform

### Phase A: Lambda Function URL

```hcl
locals {
  is_lambda = var.config.runtime == "lambda"
  is_ecs    = var.config.runtime == "ecs"

  # Render LiteLLM config.yaml from model tier map
  litellm_config = yamlencode({
    model_list = [
      for tier, model_path in var.config.model_tiers : {
        model_name    = tier
        litellm_params = {
          model  = model_path
          # Bedrock models use IAM auth — no api_key needed
          # Anthropic models use secret ref resolved at runtime
        }
      }
    ]
    litellm_settings = {
      num_retries          = 3
      request_timeout      = 600
      telemetry            = false
    }
    general_settings = {
      master_key = "os.environ/LITELLM_MASTER_KEY"
    }
  })
}

# Phase A: Lambda
resource "aws_lambda_function" "ai_gateway" {
  count         = local.is_lambda ? 1 : 0

  function_name = "${var.client_id}-${var.env}-ai-gateway"
  package_type  = "Image"
  image_uri     = "${data.tfe_outputs.ecr.outputs.repository_urls["ai-gateway"]}:${var.config.image_tag}"
  role          = aws_iam_role.ai_gateway.arn
  memory_size   = var.config.memory_mb
  timeout       = var.config.timeout_seconds

  environment {
    variables = {
      LITELLM_CONFIG_CONTENT = local.litellm_config
      BEDROCK_REGION         = var.region
      AWS_REGION_NAME        = var.region
    }
  }

  # Secrets injected via environment — Lambda reads from Secrets Manager at startup
  dynamic "environment" {
    for_each = var.config.providers.anthropic.enabled ? [1] : []
    content {
      variables = {
        ANTHROPIC_API_KEY = "arn:${data.aws_partition.current.partition}:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.client_id}-${var.env}-${var.config.providers.anthropic.api_key_secret_ref}"
      }
    }
  }
}

resource "aws_lambda_function_url" "ai_gateway" {
  count              = local.is_lambda ? 1 : 0
  function_name      = aws_lambda_function.ai_gateway[0].function_name
  authorization_type = "AWS_IAM"

  cors {
    allow_credentials = false
    allow_methods     = ["POST", "GET"]
    allow_origins     = ["*"]
  }
}
```

### IAM Role for Lambda (Bedrock + Secrets access)

```hcl
resource "aws_iam_role" "ai_gateway" {
  name = "${var.client_id}-${var.env}-ai-gateway"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Attach Bedrock invoke policy from spec-01 output
resource "aws_iam_role_policy_attachment" "bedrock" {
  role       = aws_iam_role.ai_gateway.name
  policy_arn = data.tfe_outputs.bedrock.outputs.bedrock_invoke_policy_arn
}

# Secrets Manager read for external provider keys
resource "aws_iam_role_policy" "secrets" {
  name = "read-provider-keys"
  role = aws_iam_role.ai_gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [for ref in local.provider_secret_arns : ref]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.ai_gateway.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
```

### Phase B Migration: ECS Service (future — triggered by config.runtime = "ecs")

```hcl
# Phase B: ECS service (only created when runtime = "ecs")
resource "aws_ecs_service" "ai_gateway" {
  count           = local.is_ecs ? 1 : 0
  name            = "${var.client_id}-${var.env}-ai-gateway"
  cluster         = data.tfe_outputs.ecs.outputs.cluster_arn
  task_definition = aws_ecs_task_definition.ai_gateway[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.tfe_outputs.vpc.outputs.private_subnet_ids
    security_groups  = [aws_security_group.ai_gateway_ecs[0].id]
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = data.tfe_outputs.ecs.outputs.service_connect_namespace
    service {
      port_name      = "http"
      discovery_name = "ai-gateway"
      client_alias {
        port     = 4000
        dns_name = "ai-gateway"
      }
    }
  }
}
```

---

## IAM Permissions Required (Bootstrap Role)

```
lambda:CreateFunction
lambda:DeleteFunction
lambda:UpdateFunctionCode
lambda:UpdateFunctionConfiguration
lambda:CreateFunctionUrlConfig
lambda:DeleteFunctionUrlConfig
lambda:AddPermission
iam:CreateRole
iam:AttachRolePolicy
iam:PutRolePolicy
iam:PassRole
logs:CreateLogGroup
logs:PutRetentionPolicy
```

---

## Outputs

```hcl
output "endpoint_url" {
  description = "AI gateway endpoint — all AI frameworks call this URL"
  value       = local.is_lambda ? aws_lambda_function_url.ai_gateway[0].function_url : "http://ai-gateway:4000"
}

output "function_arn" {
  description = "Lambda function ARN (Phase A only)"
  value       = local.is_lambda ? aws_lambda_function.ai_gateway[0].arn : null
}

output "gateway_role_arn" {
  description = "IAM role ARN — attach Bedrock and secrets policies here"
  value       = aws_iam_role.ai_gateway.arn
}
```

---

## Todos

### Infrastructure
- [ ] Create `workspaces/ai-gateway/` directory
- [ ] Create `workspaces/ai-gateway/main.tf` — conditional Lambda vs ECS based on `runtime`
- [ ] Create `workspaces/ai-gateway/variables.tf` — `ai_gateway_config_json` decoded variable
- [ ] Create `workspaces/ai-gateway/outputs.tf`
- [ ] Create `workspaces/ai-gateway/litellm_config/config.yaml.tpl` — LiteLLM config template
- [ ] Create `modules/aws/litellm-lambda/` — Lambda function + function URL module
- [ ] Create ECR image for LiteLLM Lambda (in `forge-core-ai` repo, not Terraform)

### Control Plane Wiring
- [ ] Add `ai-gateway` to `service_working_dirs` map
- [ ] Add dependency: `ai-gateway` requires `bedrock` and `ecr` workspaces
- [ ] Add `ai_gateway_config_json` schema validation (valid `runtime` values: `lambda`, `ecs`)

### Test Client
- [ ] Add `ai-gateway` to `test-client-dev` `services` array
- [ ] Add `ai_gateway_config_json` with `runtime: "lambda"` and Bedrock models
- [ ] Apply workspace and test endpoint with a chat completion request

---

## Verification

```bash
# 1. Get the function URL from Terraform output
GATEWAY_URL=$(terraform output -raw endpoint_url)

# 2. Test a chat completion (OpenAI-compatible)
# Note: Lambda function URL requires AWS SigV4 auth — use awscurl or set up a test caller
awscurl --service lambda --region us-east-1 \
  -X POST "${GATEWAY_URL}/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "fast",
    "messages": [{"role": "user", "content": "Say hello in one word."}],
    "max_tokens": 10
  }'
# Expected: {"choices": [{"message": {"content": "Hello"}}], ...}

# 3. Test model tier routing
awscurl --service lambda --region us-east-1 \
  -X POST "${GATEWAY_URL}/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model": "balanced", "messages": [{"role": "user", "content": "ping"}], "max_tokens": 5}'
# Expected: successful response, model = claude-3-5-sonnet in response metadata

# 4. Confirm Lambda logs show Bedrock as provider
aws logs tail /aws/lambda/test-client-dev-ai-gateway --since 5m | grep -i "bedrock"
```

**Gate:** Chat completion returns a valid response for all three tiers (`fast`, `balanced`, `powerful`)
before any AI framework can be deployed.

---

## Cost Notes

| Resource | Phase A (Lambda) | Phase B (ECS) |
|---|---|---|
| Compute | $0 idle; ~$0.0000166667/GB-second | ~$35/month (0.25 vCPU, 0.5GB, always-on) |
| Function URL / ALB | $0 (Function URL free) | ~$16/month (ALB) |
| **Total gateway infra** | **~$0 at low volume** | **~$50/month** |

Model call costs are charged by Bedrock/Anthropic, not by this blueprint.
Migrate to Phase B when gateway compute cost is justified by request volume.
