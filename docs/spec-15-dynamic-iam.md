# Spec-15: Dynamic IAM (Blast Radius Control)

**Status:** `[ ] not started`
**Phase:** Wave 1 — Security Foundations (parallel with bedrock, agent-state)
**Default depends on:** `iam` (base OIDC roles), `secure-baseline` (KMS), `vpc`
**Blocks:** any agent tool that accesses business data (customer records, orders, payments)
**Repo(s):** core-tfe-bootstrap-workspace-management

---

## Business Rule

An agent's effective permissions must be limited to exactly the data scope of the active
user's session. An agent must not be able to access data outside the invoking user's
permissions boundary, even if the agent is compromised or its reasoning loop is manipulated
via prompt injection.

---

## Goal

Provision the IAM architecture for dynamic, per-tool-call permission scoping:
- **Base execution roles**: minimal access (Bedrock, DynamoDB agent-state, SQS) — no business data
- **Tool roles**: one per tool category, assumed at invocation time with a dynamic session policy
- **Permissions Boundaries**: prevent any agent role from exceeding a defined permission ceiling
- **No wildcard resources** on any role accessible to agent frameworks

This extends (does not replace) the existing `iam` blueprint OIDC roles, which handle
Terraform-to-AWS trust. This spec handles runtime agent-to-AWS trust.

---

## Context

### Static vs Dynamic IAM

The existing `workspaces/iam/` blueprint provisions static OIDC federated roles:
Terraform workspaces assume a `TerraformDeployRole` to apply infrastructure. This is correct
for infrastructure deployment.

Runtime agents need a different model:

```
Static model (current iam blueprint):
  Fargate/Lambda task role → one IAM role → all permissions pre-attached
  Problem: if the agent is compromised, attacker has all pre-attached permissions

Dynamic model (this spec):
  Fargate/Lambda → base role (Bedrock + DynamoDB agent-state + SQS only)
                 → STS AssumeRole (tool-specific role + dynamic session policy)
                 → Temporary credentials scoped to: exact customer ID, exact action
                 Blast radius: compromised agent can only access one user's data for one operation
```

### STS Session Policy Pattern

When the reasoning loop invokes a tool, it calls STS with a session policy:

```python
# Example: agent reads customer data for session user only
sts = boto3.client('sts')
response = sts.assume_role(
    RoleArn='arn:aws:iam::ACCOUNT:role/client-dev-tool-read-customer-data',
    RoleSessionName=f'agent-{agent_id}-{execution_id}',
    Policy=json.dumps({
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Action": ["dynamodb:GetItem", "dynamodb:Query"],
            "Resource": "arn:aws:dynamodb:REGION:ACCOUNT:table/customers",
            "Condition": {
                "ForAllValues:StringEquals": {
                    "dynamodb:LeadingKeys": [session.customer_id]  # scoped to THIS user
                }
            }
        }]
    }),
    DurationSeconds=900  # 15 minutes max per tool call
)
```

The session policy is the intersection of the tool role's permissions and the dynamic policy.
The agent can never exceed the tool role's permissions, even if it constructs a broader session policy.

### Permissions Boundaries

Permissions Boundaries are IAM managed policies attached to execution roles. They define the
maximum permissions the role can ever have, regardless of what policies are attached:

```
Permissions Boundary: agent-sandbox-boundary
  Allow: Bedrock InvokeModel
  Allow: DynamoDB (agent-state tables only, by resource ARN)
  Allow: SQS (ai-queue only, by resource ARN)
  Allow: CloudWatch Logs (write only)
  Allow: X-Ray (write only)
  Deny: IAM (no role creation, no policy modification)
  Deny: S3 buckets not owned by this client environment
  Deny: RDS direct access (agents use DynamoDB, not RDS directly)
```

Even if a prompt injection tricks the agent into attaching a broader policy, the Permissions
Boundary prevents it from taking effect.

---

## `accounts.tf.json` Contract

### Input Configuration (stable)

```json
"dynamic-iam": {
  "dynamic_iam_config_json": {
    "tool_roles": {
      "read-customer-data": {
        "enabled": true,
        "services": ["dynamodb"],
        "resource_arns": [],
        "max_session_duration_seconds": 900
      },
      "write-order": {
        "enabled": false,
        "services": ["dynamodb", "sqs"],
        "resource_arns": [],
        "max_session_duration_seconds": 300
      },
      "send-notification": {
        "enabled": false,
        "services": ["ses", "sns"],
        "resource_arns": [],
        "max_session_duration_seconds": 300
      }
    },
    "permissions_boundary": {
      "allow_bedrock": true,
      "allow_agent_state_tables": true,
      "allow_ai_queue": true,
      "deny_iam_modification": true,
      "deny_direct_rds": true
    }
  }
}
```

### Implementation Notes (current)

- Tool roles are IAM roles with trust policy allowing the base execution role to assume them
- Each tool role has a Permissions Boundary attached at creation time
- `resource_arns` populated at apply time from upstream blueprint outputs (DynamoDB table ARNs from spec-03, SQS queue ARNs from spec-04)
- Session policy generation logic lives in forge-core-ai (application code) — this blueprint provisions the roles; the application generates the scoped session policies at runtime

---

## Output Contract

| Output key | Type | Stability | Consumers |
|------------|------|-----------|-----------|
| `base_execution_role_arn` | string | stable | spec-09 ECS task role, spec-02 Lambda execution role |
| `tool_role_arns` | map(string) | stable | forge-core-ai (STS AssumeRole calls) |
| `permissions_boundary_arn` | string | stable | spec-12 sandbox role, all future agent roles |
| `session_duration_seconds` | map(string) | convenience | forge-core-ai config |

---

## Terraform Resources Created

- `aws_iam_role` — base execution role (one per client environment)
- `aws_iam_role_policy` — base role inline policy (Bedrock, DynamoDB agent-state, SQS)
- `aws_iam_role` — one tool role per enabled tool category
- `aws_iam_policy` — Permissions Boundary policy
- `aws_iam_role` association — Permissions Boundary attached to all agent roles
- `aws_iam_role` trust policy — allows base role to AssumeRole on tool roles

---

## Validation Checklist

From the architecture reference:

- [ ] **Least privilege**: `terraform plan` output confirms no `"Resource": "*"` on any IAM statement in any agent-accessible role.
- [ ] **Dynamic scoping**: Integration test: agent with session for `customer_id=123` cannot read records for `customer_id=456` even after calling STS. Verified by attempting GetItem with mismatched partition key.
- [ ] **Boundary enforcement**: Attempt to attach a broader inline policy to the base execution role. Confirm the Permissions Boundary prevents the new permissions from taking effect.
- [ ] **Privilege escalation blocked**: Agent cannot call `iam:CreateRole`, `iam:AttachRolePolicy`, or `iam:PutRolePolicy`. Verified by attempting these actions with base execution role credentials.

---

## Tradeoffs

| Concern | Decision | Rationale |
|---------|----------|-----------|
| Static vs dynamic IAM | Dynamic (STS session policies) | Static roles give blast radius = all data the agent ever touches; dynamic scopes to current user session |
| Session duration | 900s max (15 min) | Limits exposure window if credentials are leaked; matches Lambda max timeout |
| Session policy generation | Application layer (forge-core-ai) | Business logic (what data scope = this user's session) belongs in app code, not Terraform |
| Permissions Boundary | Required on all agent roles | Prevents privilege escalation regardless of what policies are later attached |
| Tool role per category vs per tool | Per category | Balance between granularity and role proliferation; read-all-customer-data is one role, not one per customer |

---

## References

- [spec-03-agent-state.md](./spec-03-agent-state.md) — DynamoDB ARNs that base role needs access to
- [spec-04-ai-queue.md](./spec-04-ai-queue.md) — SQS ARNs that base role needs access to
- [spec-12-sandbox-lambda.md](./spec-12-sandbox-lambda.md) — Sandbox execution role uses Permissions Boundary from this spec
- [spec-09-ecs.md](./spec-09-ecs.md) — ECS task role is the base execution role from this spec
- [spec-ca-review.md](./spec-ca-review.md) — Standard spec template reference
