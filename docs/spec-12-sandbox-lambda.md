# Spec-12: Secure Code Execution Sandbox (Lambda)

**Status:** `[ ] not started`
**Phase:** Wave 3 — Execution Safety
**Default depends on:** `vpc`, `iam`, `secure-baseline` (KMS key)
**Blocks:** any agent capability that executes generated code or runs terminal commands
**Repo(s):** core-tfe-bootstrap-workspace-management

---

## Business Rule

Agent-generated code must execute in a fully isolated environment that cannot read internal
databases, reach internal services, or escalate to the permissions of the reasoning process
that invoked it.

---

## Goal

Provision an isolated AWS Lambda function for executing agent-generated code and terminal
commands. This is the **Execution Layer** — distinct from the **Reasoning Layer** (ai-gateway,
ECS orchestrators).

The sandbox Lambda:
- Runs with a read-only root filesystem and ephemeral `/tmp` as the only writable volume
- Sits in a dedicated VPC subnet with no route to internal database or application subnets
- Has no internet egress by default (explicit opt-in per tool requirement)
- Executes under a separate IAM role with zero overlap with the reasoning role
- Is invoked asynchronously by the reasoning loop, never called by the client directly

---

## Context

### Two Compute Roles, Two Lambdas

The current specs define one Lambda role (ai-gateway, task workers). The sandbox is a second,
fundamentally different Lambda role:

| | Reasoning Lambda (spec-02) | Execution Lambda (this spec) |
|---|---|---|
| Purpose | LiteLLM proxy, model routing | Run agent-generated code |
| Lifetime | Per-request (ms to seconds) | Per tool call (ms to minutes) |
| IAM role | Access to Bedrock, DynamoDB, SQS | Minimal — no business data access |
| Network | Standard private subnet | Isolated subnet, deny-all egress to internal |
| Filesystem | Default Lambda FS | Read-only root, ephemeral /tmp |
| Invoked by | API Gateway / client | Reasoning loop only (async invoke) |

### Why Lambda (Not ECS) for Sandboxing

Lambda's ephemeral execution model makes it a natural sandbox:
- Each invocation starts fresh — no state leaks between agent tool calls
- Cold start overhead is acceptable for tool execution (seconds, not ms-critical)
- Lambda's compute isolation (separate microVM per invocation) provides OS-level separation
- At zero traffic: $0 cost

ECS would require explicit container lifecycle management to achieve equivalent isolation.

### Network Isolation Design

```
VPC
├── private-app-subnet      ← reasoning Lambda, ECS tasks, API
├── private-db-subnet       ← RDS, ElastiCache (no route from sandbox)
└── sandbox-isolated-subnet ← Execution Lambda (this spec)
      Security Group: allow-outbound-internet-only (if tool needs it)
      Security Group: deny-all (default, no tool internet access)
      Route table: no route to private-app-subnet, no route to private-db-subnet
      NAT Gateway: disabled by default; enabled per tool if required
```

### IAM Isolation

The sandbox executes under `<client_id>-<env>-sandbox-execution-role`. This role:
- Has no access to DynamoDB, RDS, SQS, or S3 buckets used by other blueprints
- Has permission only to: write CloudWatch logs, write X-Ray traces
- The reasoning loop passes any data the tool needs as Lambda event payload (not via shared resources)
- Results are returned as Lambda response payload, not written to shared state directly

The reasoning loop writes tool results to the agent state ledger (spec-03) after receiving
the sandbox response — the sandbox itself never touches the state store.

---

## `accounts.tf.json` Contract

### Input Configuration (stable)

```json
"sandbox-lambda": {
  "sandbox_config_json": {
    "runtime": "python3.12",
    "memory_mb": 1024,
    "timeout_seconds": 300,
    "ephemeral_storage_mb": 512,
    "internet_egress": false,
    "allowed_egress_cidrs": [],
    "tools": {
      "code-interpreter": {
        "enabled": true,
        "runtime": "python3.12",
        "memory_mb": 2048,
        "timeout_seconds": 120
      },
      "terminal": {
        "enabled": false
      }
    }
  }
}
```

### Implementation Notes (current)

- `internet_egress: false` → sandbox subnet route table has no NAT Gateway attachment
- `internet_egress: true` → sandbox subnet attaches to a dedicated NAT Gateway (not shared with
  private-app subnet to prevent sandbox traffic mixing with application traffic)
- `allowed_egress_cidrs` → Security Group outbound rules; only applies when `internet_egress: true`
- Each tool type maps to a separate Lambda function with its own IAM role and security group

---

## Output Contract

| Output key | Type | Stability | Consumers |
|------------|------|-----------|-----------|
| `sandbox_function_arns` | map(string) | stable | reasoning loop (async invoke permission) |
| `sandbox_execution_role_arns` | map(string) | stable | spec-15 dynamic IAM (permissions boundary) |
| `sandbox_security_group_id` | string | stable | spec-09 ECS (network rule reference) |
| `sandbox_subnet_ids` | list(string) | stable | cross-reference for network isolation audit |

---

## Terraform Resources Created

- `aws_lambda_function` — one per enabled tool type
- `aws_iam_role` + `aws_iam_role_policy` — sandbox execution role (minimal permissions)
- `aws_security_group` — deny-all or internet-only egress depending on config
- `aws_subnet` + `aws_route_table` — isolated sandbox subnet (no internal routes)
- `aws_cloudwatch_log_group` — sandbox invocation logs (KMS encrypted)
- `aws_xray_group` — sandbox trace group (feeds spec-10 ai-obs)

---

## Validation Checklist

From the architecture reference:

- [ ] **Timeout handling**: Lambda timeout set per tool type. Reasoning loop handles timeout response gracefully (writes failed tool result to agent state, does not retry indefinitely).
- [ ] **Network segmentation**: Sandbox security group has explicit deny-all egress to `private-db-subnet` CIDR and `private-app-subnet` CIDR. Verified with VPC Flow Logs.
- [ ] **IAM isolation**: `terraform plan` confirms sandbox execution role has zero DynamoDB, SQS, S3, or Bedrock permissions. Role ARN is distinct from reasoning role ARN.

---

## Tradeoffs

| Concern | Decision | Rationale |
|---------|----------|-----------|
| Lambda vs ECS for sandbox | Lambda | Ephemeral model provides natural isolation; $0 idle; cold start acceptable for tool execution |
| Per-tool Lambda vs shared Lambda | Per-tool | Different tools need different memory/timeout/network configs; isolation boundary is cleaner |
| Internet egress default | Disabled | Most tools (code execution, data processing) need no internet. Opt-in per tool prevents accidental data exfiltration |
| Sandbox writes to shared state | Not allowed | Sandbox returns results as response payload; reasoning loop is responsible for state persistence |

---

## References

- [spec-02-ai-gateway.md](./spec-02-ai-gateway.md) — Reasoning Lambda (not the same as this)
- [spec-03-agent-state.md](./spec-03-agent-state.md) — State ledger written by reasoning loop after sandbox result
- [spec-09-ecs.md](./spec-09-ecs.md) — ECS reasoning layer that invokes sandbox
- [spec-15-dynamic-iam.md](./spec-15-dynamic-iam.md) — Permissions Boundaries applied to sandbox role
- [spec-ca-review.md](./spec-ca-review.md) — Standard spec template reference
