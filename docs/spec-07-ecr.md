# Spec-07: ECR (Container Registry)

**Status:** `[ ] not started`
**Phase:** Wave 2 — Knowledge Layer
**Depends on:** `iam`
**Blocks:** `spec-09-ecs` (ECS tasks pull images from ECR)
**Repo(s):** core-tfe-bootstrap-workspace-management

---

## Goal

Provision ECR repositories to store AI service container images. The Docker image is where
the AI framework lives — the Terraform blueprint stays framework-agnostic.

---

## Context

**Framework-agnostic principle in practice:**

The ECS task definition (spec-09) references an ECR image URL. The image contains
the AI framework (LangGraph, PydanticAI, etc.) + application code. To swap frameworks:
1. Build a new Docker image with the new framework
2. Push it to ECR under the same repository
3. Update the ECS task definition image tag
4. No Terraform change required

The `ecr` blueprint manages:
- Repository creation (one per service type)
- Security (KMS encryption, image scanning)
- Lifecycle policies (keep last N images, prevent unbounded storage growth)
- Cross-account pull access (agency deploying to client account)

---

## `accounts.tf.json` Contract

```json
"ecr": {
  "ecr_config_json": {
    "repositories": {
      "ai-engine": {
        "name_suffix": "ai-engine",
        "scan_on_push": true,
        "lifecycle_keep_tagged_count": 10,
        "lifecycle_expire_untagged_days": 7
      },
      "ai-gateway": {
        "name_suffix": "ai-gateway",
        "scan_on_push": true,
        "lifecycle_keep_tagged_count": 5,
        "lifecycle_expire_untagged_days": 3
      },
      "ai-worker": {
        "name_suffix": "ai-worker",
        "scan_on_push": true,
        "lifecycle_keep_tagged_count": 5,
        "lifecycle_expire_untagged_days": 3
      }
    },
    "image_tag_mutability": "MUTABLE",
    "cross_account_pull_role_arns": []
  }
}
```

**Repository naming**: `{client_id}-{env}-{name_suffix}` — e.g. `mindrithm-dev-ai-engine`

**`scan_on_push`**: Always true. AI workloads import many Python packages with frequent CVEs.
Scan results appear in ECR console and can be alerted via EventBridge.

**`lifecycle_keep_tagged_count`**: Retain last N tagged images. Prevents unbounded storage growth.
AI images tend to be large (2-5GB) due to ML dependencies.

---

## Workspace Structure

```
workspaces/ecr/
  main.tf      ← ECR repositories, encryption, scan config, lifecycle policies
  variables.tf ← ecr_config_json (decoded)
  outputs.tf   ← repository_urls map, repository_arns map
  data.tf      ← data.tfe_outputs.iam, secure_baseline (KMS key)
```

---

## Sample Terraform

### ECR Repositories

```hcl
locals {
  config = jsondecode(var.ecr_config_json)
}

resource "aws_ecr_repository" "repositories" {
  for_each = local.config.repositories

  name                 = "${var.client_id}-${var.env}-${each.value.name_suffix}"
  image_tag_mutability = local.config.image_tag_mutability

  # KMS encryption — keeps AI model weights and training artifacts private
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = data.tfe_outputs.secure_baseline.outputs.kms_key_arn
  }

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push
  }

  tags = merge(var.tags, {
    Name      = "${var.client_id}-${var.env}-${each.value.name_suffix}"
    blueprint = "ecr"
    service   = each.key
  })
}

# Lifecycle policy — prevent unbounded storage (AI images are large, 2-5GB each)
resource "aws_ecr_lifecycle_policy" "repositories" {
  for_each   = local.config.repositories
  repository = aws_ecr_repository.repositories[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${each.value.lifecycle_keep_tagged_count} tagged images"
        selection = {
          tagStatus   = "tagged"
          tagPrefixList = ["v", "latest", "sha-"]
          countType   = "imageCountMoreThan"
          countNumber = each.value.lifecycle_keep_tagged_count
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after ${each.value.lifecycle_expire_untagged_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = each.value.lifecycle_expire_untagged_days
        }
        action = { type = "expire" }
      }
    ]
  })
}

# Repository policy — allows ECS task execution role to pull images
resource "aws_ecr_repository_policy" "pull" {
  for_each   = local.config.repositories
  repository = aws_ecr_repository.repositories[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowECSPull"
        Effect = "Allow"
        Principal = {
          AWS = concat(
            # ECS execution role (from this account — set up in spec-09)
            ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"],
            # Optional: cross-account pull for agency CI/CD
            local.config.cross_account_pull_role_arns
          )
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}
```

### IAM Policy for CI/CD Push

```hcl
# Push policy — for GitHub Actions CI/CD pushing new images
resource "aws_iam_policy" "ecr_push" {
  name        = "${var.client_id}-${var.env}-ecr-push"
  description = "Allow CI/CD to push images to AI ECR repositories"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GetAuthToken"
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]  # GetAuthorizationToken requires * resource
      },
      {
        Sid    = "PushImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = [for k, r in aws_ecr_repository.repositories : r.arn]
      },
      {
        Sid    = "KmsForEncryptedImages"
        Effect = "Allow"
        Action = ["kms:GenerateDataKey", "kms:Decrypt", "kms:DescribeKey"]
        Resource = [data.tfe_outputs.secure_baseline.outputs.kms_key_arn]
      }
    ]
  })
}

# Pull policy — for ECS task execution role
resource "aws_iam_policy" "ecr_pull" {
  name        = "${var.client_id}-${var.env}-ecr-pull"
  description = "Allow ECS task execution role to pull images"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = [for k, r in aws_ecr_repository.repositories : r.arn]
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
ecr:CreateRepository
ecr:DeleteRepository
ecr:PutLifecyclePolicy
ecr:SetRepositoryPolicy
ecr:DeleteRepositoryPolicy
ecr:PutImageScanningConfiguration
iam:CreatePolicy
iam:DeletePolicy
```

---

## Outputs

```hcl
output "repository_urls" {
  description = "Map of repository key → repository URL — used in ECS task definitions and CI push commands"
  value       = { for k, r in aws_ecr_repository.repositories : k => r.repository_url }
}

output "repository_arns" {
  description = "Map of repository key → repository ARN — used in IAM policies"
  value       = { for k, r in aws_ecr_repository.repositories : k => r.arn }
}

output "push_policy_arn" {
  description = "IAM policy ARN for image push — attach to CI/CD OIDC role"
  value       = aws_iam_policy.ecr_push.arn
}

output "pull_policy_arn" {
  description = "IAM policy ARN for image pull — attach to ECS task execution role"
  value       = aws_iam_policy.ecr_pull.arn
}
```

---

## Todos

### Infrastructure
- [ ] Create `workspaces/ecr/` directory
- [ ] Create `workspaces/ecr/main.tf` — repositories, lifecycle policies, repository policies
- [ ] Create `workspaces/ecr/variables.tf` — `ecr_config_json` variable
- [ ] Create `workspaces/ecr/outputs.tf`
- [ ] Create `workspaces/ecr/data.tf` — secure_baseline KMS, caller identity

### Control Plane Wiring
- [ ] Add `ecr` to `service_working_dirs` map
- [ ] Add dependency: requires `iam` and `secure-baseline`
- [ ] Expose `pull_policy_arn` output — consumed by `spec-09-ecs` task execution role
- [ ] Expose `push_policy_arn` output — consumed by `iam` blueprint CI/CD role

### Seed Images
- [ ] Create seed (placeholder) images for each repository so ECS task definitions can be created
  without requiring a real image on first deploy (use `public.ecr.aws/amazonlinux/amazonlinux:latest`
  as placeholder, swapped by CI/CD on first real build)

### Test Client
- [ ] Add `ecr` to `test-client-dev` services
- [ ] Apply and verify 3 repositories exist with lifecycle policies
- [ ] Push a test image and confirm scan result appears

---

## Verification

```bash
# 1. List repositories
aws ecr describe-repositories \
  --query "repositories[?contains(repositoryName, 'test-client-dev-ai')].repositoryName"
# Expected: ["test-client-dev-ai-engine", "test-client-dev-ai-gateway", "test-client-dev-ai-worker"]

# 2. Confirm lifecycle policy set
aws ecr get-lifecycle-policy \
  --repository-name "test-client-dev-ai-engine" \
  --query "lifecyclePolicyText" | jq .
# Expected: JSON policy with keep-tagged and expire-untagged rules

# 3. Confirm scan on push enabled
aws ecr describe-repositories \
  --repository-names "test-client-dev-ai-engine" \
  --query "repositories[0].imageScanningConfiguration.scanOnPush"
# Expected: true

# 4. Test push (requires Docker login)
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  $(aws ecr describe-repositories \
    --repository-names test-client-dev-ai-engine \
    --query "repositories[0].repositoryUri" --output text | cut -d/ -f1)

docker pull public.ecr.aws/amazonlinux/amazonlinux:latest
docker tag public.ecr.aws/amazonlinux/amazonlinux:latest \
  $(terraform output -json repository_urls | jq -r '."ai-engine"'):seed

docker push $(terraform output -json repository_urls | jq -r '."ai-engine"'):seed
# Expected: push succeeds and image appears in ECR console
```

**Gate:** All repositories created; lifecycle policies set; test image push succeeds; scan result visible.

---

## Cost Notes

| Resource | Cost |
|---|---|
| ECR storage | $0.10/GB/month |
| ECR data transfer (within AWS) | Free |
| ECR data transfer (to internet) | $0.09/GB |
| Image scan (basic) | Free |
| Image scan (enhanced, Inspector) | $0.09/image layer scanned |

**Typical AI image size**: 3-5GB (PyTorch, LangGraph, FastAPI, models).
At 10 images per repository × 3 repositories × 4GB = ~$12/month storage.

Lifecycle policies cap this: max ~10 × 4GB × 3 = 120GB = ~$12/month.
