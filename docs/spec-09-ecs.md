# Spec-09: ECS Fargate AI Runtime

**Status:** `[ ] not started`
**Phase:** Wave 3 — Scale Compute (Phase B)
**Depends on:** `vpc`, `spec-07-ecr`, `secrets`, `iam`, `spec-01-bedrock`, `spec-03-agent-state`, `spec-04-ai-queue`
**Blocks:** nothing (activates when Lambda limits are exceeded)
**Repo(s):** core-tfe-bootstrap-workspace-management

---

## Goal

Provision ECS Fargate infrastructure for long-running AI orchestrators.

This is **Phase B** infrastructure — only add it when:
- Lambda cold-start latency is unacceptable (>3s is noticeable in chat)
- Agent orchestrators exceed Lambda's 15-minute execution limit
- Streaming SSE requires a persistent connection (Lambda Function URLs do support streaming
  but have buffering limitations)
- Request volume exceeds Lambda concurrency limits (~1K concurrent)

At launch, the existing `lambda` blueprint covers short AI tasks. This blueprint activates
when the Lambda-first approach hits its ceiling.

---

## Context

**Compute split from forge-core-ai CLAUDE.md:**
```
@task nodes (short, stateless)  → Lambda (existing lambda blueprint)
@entrypoint orchestrators (long-running, stateful) → ECS Fargate (this blueprint)
```

**Why ECS over EKS?**
ECS Fargate removes all node management. AI workload patterns are container-burst, not
cluster-sustained. EKS adds Kubernetes overhead that isn't justified until sustained throughput
and complex scheduling requirements emerge.

**Framework-agnostic**: The ECS task definition references an ECR image URL. The container
holds the AI framework. Swapping LangGraph for PydanticAI = push new image + update image tag.
No Terraform change.

**Per-client cluster**: One ECS cluster per client environment. Not a shared cluster.
Provides network isolation and IAM separation between clients.

---

## `accounts.tf.json` Contract

```json
"ecs": {
  "ecs_config_json": {
    "cluster": {
      "name_suffix": "ai",
      "enable_container_insights": true
    },
    "services": {
      "ai-engine": {
        "image_repo_key": "ai-engine",
        "image_tag": "latest",
        "cpu": 1024,
        "memory_mb": 2048,
        "desired_count": 1,
        "min_count": 0,
        "max_count": 10,
        "port": 8000,
        "health_check_path": "/health",
        "spot_percentage": 0,
        "needs_vpc": true,
        "needs_db": true,
        "secret_refs": {
          "AI_GATEWAY_URL": "",
          "ANTHROPIC_API_KEY": "anthropic_api_key"
        },
        "env_vars": {
          "LOG_LEVEL": "info",
          "PLATFORM": "ecs"
        }
      }
    },
    "autoscaling": {
      "ai-engine": {
        "cpu_target": 70,
        "scale_in_cooldown": 300,
        "scale_out_cooldown": 60
      }
    }
  }
}
```

**`spot_percentage`**: Set `0` for production (on-demand only), `70` for dev/workbench
(70% Spot, 30% on-demand — ~60% cost reduction with acceptable interruption risk).

**`min_count: 0`**: Scale to zero when idle. Combined with Fargate Spot, dev clusters can
cost nothing when not in use.

---

## Workspace Structure

```
workspaces/ecs/
  main.tf          ← Cluster, task definitions, services, auto-scaling
  iam.tf           ← Task execution role, task role (separate for clarity)
  networking.tf    ← Security groups, Service Connect namespace
  autoscaling.tf   ← Application Auto Scaling targets and policies
  variables.tf     ← ecs_config_json (decoded)
  outputs.tf       ← cluster_arn, service_arns, service_connect_namespace
  data.tf          ← vpc, ecr, secrets, agent-state, ai-queue, bedrock outputs
```

---

## Sample Terraform

### ECS Cluster

```hcl
locals {
  config = jsondecode(var.ecs_config_json)
}

resource "aws_ecs_cluster" "ai" {
  name = "${var.client_id}-${var.env}-${local.config.cluster.name_suffix}"

  setting {
    name  = "containerInsights"
    value = local.config.cluster.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(var.tags, {
    Name      = "${var.client_id}-${var.env}-ai"
    blueprint = "ecs"
  })
}

# Service Connect namespace for intra-cluster service discovery
resource "aws_service_discovery_http_namespace" "ai" {
  name        = "${var.client_id}-${var.env}-ai"
  description = "Service Connect namespace for AI services"
}
```

### Task Roles (IAM)

```hcl
# ECS Task Execution Role — pulls images from ECR, reads secrets, writes logs
resource "aws_iam_role" "ecs_exec" {
  name = "${var.client_id}-${var.env}-ecs-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec_managed" {
  role       = aws_iam_role.ecs_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Attach ECR pull policy from spec-07
resource "aws_iam_role_policy_attachment" "ecr_pull" {
  role       = aws_iam_role.ecs_exec.name
  policy_arn = data.tfe_outputs.ecr.outputs.pull_policy_arn
}

# ECS Task Role — runtime permissions for the AI engine
resource "aws_iam_role" "ai_engine_task" {
  name = "${var.client_id}-${var.env}-ai-engine-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Attach Bedrock invocation policy from spec-01
resource "aws_iam_role_policy_attachment" "bedrock" {
  role       = aws_iam_role.ai_engine_task.name
  policy_arn = data.tfe_outputs.bedrock.outputs.bedrock_invoke_policy_arn
}

# Attach agent-state read-write policy from spec-03
resource "aws_iam_role_policy_attachment" "agent_state" {
  role       = aws_iam_role.ai_engine_task.name
  policy_arn = data.tfe_outputs.agent_state.outputs.readwrite_policy_arn
}

# Attach SQS receive policy from spec-04
resource "aws_iam_role_policy_attachment" "queue_receive" {
  role       = aws_iam_role.ai_engine_task.name
  policy_arn = data.tfe_outputs.ai_queue.outputs.receive_policy_arns["tasks"]
}
```

### ECS Task Definition

```hcl
resource "aws_ecs_task_definition" "services" {
  for_each = local.config.services

  family                   = "${var.client_id}-${var.env}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory_mb
  execution_role_arn       = aws_iam_role.ecs_exec.arn
  task_role_arn            = aws_iam_role.ai_engine_task.arn

  container_definitions = jsonencode([{
    name  = each.key
    image = "${data.tfe_outputs.ecr.outputs.repository_urls[each.value.image_repo_key]}:${each.value.image_tag}"

    portMappings = each.value.port != null ? [{
      containerPort = each.value.port
      protocol      = "tcp"
      name          = "http"  # Service Connect name
    }] : []

    environment = [
      for k, v in each.value.env_vars : { name = k, value = v }
    ]

    # Secrets from Secrets Manager — referenced by ARN
    secrets = [
      for k, secret_ref in each.value.secret_refs :
      {
        name      = k
        valueFrom = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.client_id}-${var.env}-${secret_ref}"
      } if secret_ref != ""
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/${var.client_id}-${var.env}/${each.key}"
        awslogs-region        = var.region
        awslogs-stream-prefix = "ecs"
        awslogs-create-group  = "true"
      }
    }

    healthCheck = each.value.health_check_path != null ? {
      command     = ["CMD-SHELL", "curl -f http://localhost:${each.value.port}${each.value.health_check_path} || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    } : null
  }])
}
```

### ECS Service + Auto-Scaling

```hcl
resource "aws_ecs_service" "services" {
  for_each = local.config.services

  name            = "${var.client_id}-${var.env}-${each.key}"
  cluster         = aws_ecs_cluster.ai.id
  task_definition = aws_ecs_task_definition.services[each.key].arn
  desired_count   = each.value.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.tfe_outputs.vpc.outputs.private_subnet_ids
    security_groups  = [aws_security_group.ai_service[each.key].id]
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.ai.arn
    service {
      port_name = "http"
      client_alias {
        port     = each.value.port
        dns_name = each.key  # reachable as http://{service-name}:{port} within cluster
      }
    }
  }

  # Fargate Spot capacity provider
  dynamic "capacity_provider_strategy" {
    for_each = each.value.spot_percentage > 0 ? [1] : []
    content {
      capacity_provider = "FARGATE_SPOT"
      weight            = each.value.spot_percentage
    }
  }

  dynamic "capacity_provider_strategy" {
    for_each = each.value.spot_percentage > 0 ? [1] : []
    content {
      capacity_provider = "FARGATE"
      weight            = 100 - each.value.spot_percentage
      base              = 1  # Always keep 1 on-demand task
    }
  }

  lifecycle {
    ignore_changes = [desired_count]  # Managed by auto-scaling after initial deploy
  }
}

# Application Auto Scaling
resource "aws_appautoscaling_target" "services" {
  for_each = local.config.services

  max_capacity       = each.value.max_count
  min_capacity       = each.value.min_count
  resource_id        = "service/${aws_ecs_cluster.ai.name}/${aws_ecs_service.services[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  for_each = local.config.autoscaling

  name               = "${var.client_id}-${var.env}-${each.key}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.services[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.services[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.services[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.cpu_target
    scale_in_cooldown  = each.value.scale_in_cooldown
    scale_out_cooldown = each.value.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
```

---

## IAM Permissions Required (Bootstrap Role)

```
ecs:CreateCluster, ecs:DeleteCluster
ecs:RegisterTaskDefinition, ecs:DeregisterTaskDefinition
ecs:CreateService, ecs:UpdateService, ecs:DeleteService
ecs:DescribeClusters, ecs:DescribeServices, ecs:DescribeTaskDefinition
application-autoscaling:RegisterScalableTarget, application-autoscaling:PutScalingPolicy
iam:CreateRole, iam:AttachRolePolicy, iam:PassRole
servicediscovery:CreateHttpNamespace, servicediscovery:DeleteNamespace
logs:CreateLogGroup, logs:PutRetentionPolicy
```

---

## Outputs

```hcl
output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.ai.arn
}

output "cluster_name" {
  description = "ECS cluster name — used by Service Connect namespace"
  value       = aws_ecs_cluster.ai.name
}

output "service_arns" {
  description = "Map of service key → ECS service ARN"
  value       = { for k, s in aws_ecs_service.services : k => s.id }
}

output "service_connect_namespace" {
  description = "Service Connect namespace ARN — used by sibling services to discover this cluster"
  value       = aws_service_discovery_http_namespace.ai.arn
}

output "task_role_arn" {
  description = "ECS task IAM role ARN — attach additional policies here for new service types"
  value       = aws_iam_role.ai_engine_task.arn
}
```

---

## Todos

### Infrastructure
- [ ] Create `workspaces/ecs/main.tf` — cluster, task definitions, services
- [ ] Create `workspaces/ecs/iam.tf` — execution role, task role, policy attachments
- [ ] Create `workspaces/ecs/networking.tf` — security groups, Service Connect namespace
- [ ] Create `workspaces/ecs/autoscaling.tf` — Application Auto Scaling
- [ ] Create `workspaces/ecs/variables.tf` — `ecs_config_json` variable
- [ ] Create `workspaces/ecs/outputs.tf`
- [ ] Create `workspaces/ecs/data.tf` — vpc, ecr, bedrock, agent-state, ai-queue outputs
- [ ] Create `modules/aws/ecs-ai-service/` — reusable ECS Fargate service module

### Control Plane Wiring
- [ ] Add `ecs` to `service_working_dirs` map
- [ ] Add dependency rules: requires `vpc`, `ecr`, `secrets`, `iam`, `bedrock`
- [ ] Validate `ecs` cannot be added without `ecr` (image storage dependency)

### Migration from Lambda (Phase A → Phase B)
- [ ] When `ai-gateway.runtime` changes from `"lambda"` to `"ecs"`:
  - ai-gateway workspace must be re-applied
  - ECS service endpoint replaces Lambda function URL
  - No forge-core-ai framework code changes needed

### Test Client
- [ ] Add `ecs` to `test-client-dev` services (after ecr, bedrock are deployed)
- [ ] Apply and verify ECS cluster + 1 service running with desired_count=1
- [ ] Confirm health check is passing

---

## Verification

```bash
# 1. List ECS services
aws ecs list-services \
  --cluster "test-client-dev-ai" \
  --query "serviceArns"
# Expected: ARN for ai-engine service

# 2. Confirm service is running
aws ecs describe-services \
  --cluster "test-client-dev-ai" \
  --services "test-client-dev-ai-engine" \
  --query "services[0].{status:status,running:runningCount,desired:desiredCount}"
# Expected: {"status":"ACTIVE","running":1,"desired":1}

# 3. Confirm health check passing
aws ecs describe-tasks \
  --cluster "test-client-dev-ai" \
  --tasks $(aws ecs list-tasks --cluster test-client-dev-ai --query taskArns[0] --output text) \
  --query "tasks[0].containers[0].healthStatus"
# Expected: "HEALTHY"

# 4. Test Service Connect DNS (from within the cluster)
# From another ECS task or bastion:
curl http://ai-engine:8000/health
# Expected: {"status": "ok"}
```

**Gate:** Service ACTIVE, runningCount = desiredCount, health check HEALTHY.

---

## Cost Notes

| Resource | Spot=0% (prod) | Spot=70% (dev) |
|---|---|---|
| 1 vCPU, 2GB Fargate | ~$35/month | ~$13/month |
| 0.25 vCPU, 0.5GB (gateway) | ~$9/month | ~$3/month |
| CloudWatch Container Insights | ~$0.35/task/month | ~$0.35/task/month |

**Scale to zero**: With `min_count = 0`, dev services can scale to zero overnight.
CloudWatch alarm or scheduled scaling can wake them up on demand.

**When to activate ECS (from Lambda):**
- Cold start p99 > 3 seconds AND user-facing
- Task duration > 14 minutes (approaching Lambda max)
- Concurrent requests > 800 (approaching Lambda burst limit)
- Streaming SSE with >30s hold-time needed
