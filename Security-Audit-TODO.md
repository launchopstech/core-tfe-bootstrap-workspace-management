# Security Audit — Remediation Spec

Audit date: 2026-04-02
Standards: CIS AWS Foundations Benchmark v1.4.0, NIST 800-53, FedRAMP Moderate Baseline

Each finding below is self-contained: what the problem is, where it lives, and exactly what to change.

---

## Priority 1 — FedRAMP Blockers

---

### SEC-01 — IAM wildcards in TerraformDeployPolicy

**File:** `bootstrap/cfn-terraform-bootstrap.yaml`
**NIST:** AC-3, AC-6
**CIS:** 5.1

**Problem:**
Every service section uses `service:*` on `Resource: "*"`. A compromised HCP Terraform workspace has full control of the provisioned AWS surface. The explicit deny statements at the bottom of the policy are correct but do not compensate for overly broad allows.

Affected sections (by Sid):
- `EC2VPC` — `ec2:*`
- `EKS` — `eks:*`
- `RDS` — `rds:*`
- `Lambda` — `lambda:*`
- `APIGateway` — `apigateway:*`
- `WAFv2` — `wafv2:*`
- `Route53` — `route53:*`
- `ACM` — `acm:*`
- `S3` — `s3:*`
- `KMS` — `kms:*`
- `Observability` — `cloudtrail:*`, `config:*`, `guardduty:*`, `securityhub:*`, `access-analyzer:*`
- `Monitoring` — `logs:*`, `cloudwatch:*`, `events:*`, `sns:*`
- `ParameterAndSecrets` — `ssm:*`, `secretsmanager:*`

**Fix:**
Replace each wildcard action list with the minimum set of actions Terraform actually invokes for that service. Use `terraform plan` output and AWS CloudTrail from a test apply to enumerate the real action set, then lock it down.

Example for Lambda:
```yaml
# Before
- Action: lambda:*

# After
- Action:
    - lambda:CreateFunction
    - lambda:UpdateFunctionCode
    - lambda:UpdateFunctionConfiguration
    - lambda:GetFunction
    - lambda:DeleteFunction
    - lambda:AddPermission
    - lambda:RemovePermission
    - lambda:GetPolicy
    - lambda:CreateEventSourceMapping
    - lambda:DeleteEventSourceMapping
    - lambda:GetEventSourceMapping
    - lambda:TagResource
    - lambda:UntagResource
    - lambda:ListTags
    - lambda:PutFunctionConcurrency
    - lambda:DeleteFunctionConcurrency
    - lambda:PublishLayerVersion
    - lambda:GetLayerVersion
    - lambda:DeleteLayerVersion
```

Do the same enumeration for ec2, rds, eks, apigateway, wafv2, route53, acm, s3, kms, and the observability/monitoring/secrets groups.

---

### SEC-02 — `iam:PassRole` not restricted to specific role ARNs

**File:** `bootstrap/cfn-terraform-bootstrap.yaml` (PassRole statement)
**NIST:** AC-6
**CIS:** 5.3

**Problem:**
`iam:PassRole` is allowed on `Resource: "*"` with a service condition. The service condition prevents passing roles to arbitrary services, but a compromised workspace could create a highly privileged role and pass it to one of the allowed services (e.g., EC2, Lambda).

**Current:**
```yaml
Effect: Allow
Action: iam:PassRole
Resource: "*"
Condition:
  StringEquals:
    iam:PassedToService:
      - ec2.amazonaws.com
      - eks.amazonaws.com
      - lambda.amazonaws.com
      - rds.amazonaws.com
```

**Fix:**
Restrict `Resource` to a naming pattern matching only roles this repo provisions:
```yaml
Effect: Allow
Action: iam:PassRole
Resource:
  - !Sub "arn:aws:iam::${AWS::AccountId}:role/terraform-*"
  - !Sub "arn:aws:iam::${AWS::AccountId}:role/client-*"
Condition:
  StringEquals:
    iam:PassedToService:
      - ec2.amazonaws.com
      - eks.amazonaws.com
      - lambda.amazonaws.com
      - rds.amazonaws.com
```

Adjust the role name prefixes to match whatever naming convention is used by the workspace modules.

---

### SEC-03 — CloudTrail / Config / GuardDuty not enforced in prod

**File:** `modules/aws/secure-baseline/variables.tf`, `modules/aws/secure-baseline/main.tf`
**NIST:** AU-2, AU-6, CA-7
**CIS:** 2.1, 3.2

**Problem:**
`enable_cloudtrail`, `enable_config`, `enable_guardduty`, and `enable_security_hub` all default to `true` but can be set to `false` with no guardrail. Dev accounts already disable all four for cost savings. Nothing prevents the same from being applied to prod or workbench environments.

**Fix:**
Add a lifecycle precondition to `modules/aws/secure-baseline/main.tf` (attach to an existing `terraform_data` resource or create one):

```hcl
resource "terraform_data" "enforce_audit_controls" {
  lifecycle {
    precondition {
      condition = !(contains(["prod", "workbench"], var.environment)) || (
        var.enable_cloudtrail &&
        var.enable_config &&
        var.enable_guardduty &&
        var.enable_security_hub
      )
      error_message = "Production and workbench environments require enable_cloudtrail, enable_config, enable_guardduty, and enable_security_hub to all be true."
    }
  }
}
```

---

## Priority 2 — Short-term Hardening

---

### SEC-04 — CloudWatch log groups not KMS-encrypted

**Files:**
- `modules/aws/api-gateway/deployment.tf` — API Gateway access log group
- `modules/aws/waf-web-acl/main.tf` — WAF log group

**NIST:** SC-28.1
**CIS:** 2.2.2

**Problem:**
Both log groups are created without `kms_key_id`. Lambda log groups already use `cloudwatch_logs_kms_key_id`. API access logs and WAF decision logs may contain request metadata and should be encrypted with a customer-managed key.

**Fix for `modules/aws/api-gateway/deployment.tf`:**
```hcl
# Add kms_key_id to the existing log group resource
resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/api-gateway/${var.api_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn   # add this
  tags              = local.base_tags
}
```

Add `kms_key_arn` as a required input variable to `modules/aws/api-gateway/variables.tf` and thread it through from `workspaces/api/main.tf` using `local.kms_key_arn` (already available in locals).

**Fix for `modules/aws/waf-web-acl/main.tf`:**
```hcl
resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = local.normalized_logging.retention_days
  kms_key_id        = var.kms_key_arn   # add this
  tags              = local.base_tags
}
```

Add `kms_key_arn` to `modules/aws/waf-web-acl/variables.tf` and thread through from `workspaces/waf/main.tf`.

Note: KMS key must have a resource policy granting `logs.amazonaws.com` permission to use it. Add this grant to the KMS key policy in `modules/aws/secure-baseline/` or wherever the key is managed.

---

### SEC-05 — `data_trace_enabled = true` in non-prod API Gateway

**File:** `modules/aws/api-gateway/deployment.tf`
**NIST:** SC-7.1

**Problem:**
```hcl
data_trace_enabled = var.environment != "prod"
```

When `true`, API Gateway logs full request and response payloads to CloudWatch. This includes Authorization headers, bearer tokens, and any PII in request bodies. Even in dev/qa, this is a data exfiltration risk if log access is misconfigured.

**Fix:**
```hcl
data_trace_enabled = false
```

If request body inspection is needed during development, use AWS X-Ray sampling or a short-lived manual toggle via the console — not a permanent config-driven flag.

---

### SEC-06 — RDS does not enforce TLS in-transit

**Files:** `modules/aws/rds-secure/main.tf`, `modules/aws/rds-aurora/main.tf`
**NIST:** SC-8

**Problem:**
Storage encryption is correctly set (`storage_encrypted = true`, `kms_key_id` wired). However, neither module forces encrypted connections. By default, clients can connect to PostgreSQL/MySQL over plaintext.

**Fix:**
Add a parameter group that enforces SSL. For PostgreSQL:
```hcl
resource "aws_db_parameter_group" "force_ssl" {
  name   = "${var.identifier}-force-ssl"
  family = var.family   # e.g. "postgres15"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}
```

Pass this parameter group to the RDS instance and add it to the Aurora cluster as well. After applying, a reboot is required for the setting to take effect.

---

## Priority 3 — Medium-term Hardening

---

### SEC-07 — VPC Flow Logs silently disabled when secure-baseline is missing

**File:** `modules/aws/vpc/main.tf`
**NIST:** AU-2, SC-7

**Problem:**
```hcl
enable_flow_log = var.logs_bucket_arn != null
```

If `logs_bucket_arn` is `null` (secure-baseline not yet applied or skipped), flow logs are silently disabled. There is no warning or error.

**Fix:**
Add a precondition:
```hcl
resource "terraform_data" "vpc_flow_log_check" {
  lifecycle {
    precondition {
      condition     = var.logs_bucket_arn != null
      error_message = "logs_bucket_arn is required for VPC Flow Logs. Deploy secure-baseline before VPC."
    }
  }
}
```

---

### SEC-08 — Lambda security group allows all outbound traffic

**File:** `modules/aws/lambda-function/networking.tf`
**NIST:** SC-7

**Problem:**
```hcl
resource "aws_security_group_rule" "lambda_egress" {
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}
```

A compromised Lambda can reach any host on any port. This is the AWS default but is not least-privilege.

**Fix:**
Parameterise egress with a variable defaulting to the current behaviour (for backwards compatibility), with a note to tighten per service:
```hcl
variable "egress_cidr_blocks" {
  description = "CIDR blocks allowed for Lambda outbound traffic. Default allows all; restrict for sensitive workloads."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
```

For `api` and `lambda` workspaces, override this to VPC CIDR + VPC endpoint CIDRs only, removing the public internet egress.

---

### SEC-09 — OAuth token ID not validated

**File:** `bootstrap-accounts/workspaces.tf`
**NIST:** IA-5

**Problem:**
`var.aws_core_oauth_token_id` is used directly without verifying it is a valid, active token in the HCP Terraform organization. An incorrect value causes workspace creation to succeed but VCS triggers to silently fail.

**Fix:**
Add a `data "tfe_oauth_client"` lookup and cross-check the ID before creating workspaces:
```hcl
data "tfe_oauth_client" "vcs" {
  organization  = var.organization
  oauth_token_id = var.aws_core_oauth_token_id
}
```

If the token doesn't exist, the data source will error at plan time with a clear message rather than producing silently broken workspaces.

---

### SEC-10 — Sensitive workspace variables not marked `sensitive = true`

**Files:** `workspaces/api/variables.tf`, `workspaces/account-portal/variables.tf`, `workspaces/waf/variables.tf`
**NIST:** SC-28

**Problem:**
`api_config_json`, `waf_config_json`, `project_requests_json`, and similar variables are `type = any` without `sensitive = true`. Their full contents appear in `terraform plan` output and HCP Terraform UI. If these configs ever carry auth provider URLs, CORS origins, or other semi-sensitive data, they are exposed.

**Fix:**
For all JSON config variables that may carry sensitive data:
```hcl
variable "api_config_json" {
  type      = any
  sensitive = true
}
```

Note: marking a variable sensitive propagates to all outputs derived from it, so any outputs that reference these variables must also be marked `sensitive = true` or explicitly `nonsensitive()` where safe.

---

## Tracking

| ID | Title | Priority | Status |
|----|-------|----------|--------|
| SEC-01 | IAM wildcards in TerraformDeployPolicy | 1 — FedRAMP blocker | open |
| SEC-02 | PassRole not restricted to specific role ARNs | 1 — FedRAMP blocker | open |
| SEC-03 | Audit controls not enforced in prod | 1 — FedRAMP blocker | open |
| SEC-04 | CloudWatch log groups not KMS-encrypted | 2 — Short-term | open |
| SEC-05 | data_trace_enabled in non-prod | 2 — Short-term | open |
| SEC-06 | RDS does not enforce TLS in-transit | 2 — Short-term | open |
| SEC-07 | VPC Flow Logs silently disabled | 3 — Medium-term | open |
| SEC-08 | Lambda allows all outbound traffic | 3 — Medium-term | open |
| SEC-09 | OAuth token ID not validated | 3 — Medium-term | open |
| SEC-10 | Sensitive variables not marked | 3 — Medium-term | open |
