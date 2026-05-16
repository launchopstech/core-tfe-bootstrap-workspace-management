# Spec Gap Analysis — Agentic Infrastructure Architecture Review

**Date:** 2026-05-16
**Input:** 6-section agentic infrastructure architecture reference
**Scope:** `docs/spec-00` through `docs/spec-11`
**Status:** Action required — 3 new specs, 7 spec updates, before Terraform implementation

---

## Summary

| Category | Count |
|----------|-------|
| New blueprints required | 3 |
| Existing specs — major updates | 4 |
| Existing specs — minor updates | 4 |
| Compute model confirmed | Lambda-first (ECS = Phase B) |

---

## Decision Log

| Decision | Outcome |
|----------|---------|
| ECS Fargate role | Lambda-first retained. ECS = Phase B when Lambda limits hit. `spec-12-sandbox-lambda` is a new isolated Lambda for code execution, not a reasoning layer replacement. |

---

## New Blueprints Required

### spec-12: Secure Code Sandbox (Lambda)

**Source:** §1 Agentic Execution & Secure Code Sandboxing

The architecture distinguishes between two Lambda use cases that the current specs conflate:

| Lambda Type | Current specs | Gap |
|-------------|--------------|-----|
| Reasoning Lambda | ai-gateway (spec-02) — LiteLLM proxy | Already spec'd |
| Execution Lambda | Not spec'd | **Missing** — needs spec-12 |

The Execution Lambda is where an agent runs generated code or terminal commands. It requires
fundamentally different security configuration than the reasoning Lambda:

- Dedicated VPC subnet with no route to internal database subnets
- No NAT Gateway / no internet egress unless the specific tool requires it
- Read-only root filesystem
- Ephemeral `/tmp` only writable volume
- Separate IAM execution role — zero overlap with reasoning role
- Security Group with explicit deny-all egress to internal corporate subnets

**Severity:** High — must be spec'd before any agent tool-execution capability is implemented

---

### spec-13: EventBridge Event Routing

**Source:** §3 Asynchronous Message Mesh & State/Graph Ledger

The current spec-04 (ai-queue) covers SQS for task dispatch and HITL approval queuing.
EventBridge is a separate concern — routing system-level events to downstream consumers:

| Event | Source | Target(s) |
|-------|--------|-----------|
| `agent.task.completed` | ECS / Lambda worker | Notification service, monitoring |
| `agent.approval.required` | Reasoning loop | HITL queue + WebSocket push (spec-14) |
| `agent.task.failed` | DLQ trigger | Alert SNS, dead-letter processing |
| `agent.step.completed` | State ledger | Audit log |

SQS handles task queuing (backpressure, delivery guarantees). EventBridge handles event fan-out
(routing to multiple consumers without tight coupling). These are complementary, not redundant.

**Severity:** Medium — needed before HITL workflow is fully wired

---

### spec-14: Real-Time Streaming (WebSocket)

**Source:** §5 Frontend Streaming & Real-Time Connection Layer

No current spec covers the persistent client connection layer. The frontend needs:
- Token-by-token streaming as the agent generates responses
- Agent "thought" broadcasting (tool calls in progress, step updates)
- HITL interruption — push `AWAITING_APPROVAL` state to UI without polling
- Long session support — ping/pong heartbeat to keep connections alive beyond API Gateway's
  default 10-minute idle timeout

Two implementation options:
- **API Gateway WebSockets** — lower cost, requires custom connection management
- **AWS AppSync** — managed GraphQL subscriptions, simpler fan-out, higher cost

**Severity:** Medium — needed before any streaming UI is implemented

---

## Existing Specs — Major Updates Required

### spec-03: Agent State (DynamoDB) — Idempotency & State Ledger

**Source:** §3 Asynchronous Message Mesh

**Current state:** spec-03 defines two tables (checkpoints, memory) with TTL and partition key format.

**Missing:**

1. **Idempotency schema** — SQS delivers at-least-once. If a worker Lambda retries a message,
   the agent must not execute the same tool twice. Fix: add `ExecutionID` + `StepNumber` as
   required fields on every DynamoDB write, with a condition expression:
   ```
   condition: attribute_not_exists(ExecutionID) OR StepNumber < :new_step
   ```
   This must be in the spec so the Terraform DynamoDB schema includes these GSI/sort key patterns.

2. **Optimistic locking** — concurrent sub-agents (parallel tool calls) must not overwrite
   each other's state. Fix: add a `version` attribute with conditional update:
   ```
   condition: version = :expected_version
   UpdateExpression: SET version = version + 1, ...
   ```

3. **State ledger model** — the spec describes "checkpoints" but the architecture requires a
   full execution graph ledger: current step number, list of past decisions, tool output cache,
   variable context map. The DynamoDB item schema needs to be explicit about these fields so
   the IAM spec (spec-15) can scope read/write permissions correctly.

4. **EFS cross-reference** — ECS Fargate containers should mount EFS for in-flight state
   (agent local variables mid-loop) before committing to DynamoDB. Add a note that spec-09
   EFS mount is the write-ahead layer; DynamoDB is the durable ledger.

**Severity:** High — DynamoDB schema decisions made here affect IAM, app code, and observability

---

### spec-06: Vector Store — Dual-Backend & Tenant Isolation

**Source:** §2 Vector & Memory Layer

**Current state:** spec-06 treats pgvector, OpenSearch Serverless, and Bedrock KB as
mutually exclusive alternatives. Client picks one.

**Gap:** The architecture text recommends running **both** OpenSearch and Aurora pgvector
simultaneously for different query patterns:

| Backend | Best for | Why separate |
|---------|----------|-------------|
| Aurora pgvector | Tightly coupled metadata + vector filtering ("Find last 5 invoices from Company X mentioning server maintenance") | SQL JOIN on structured fields + vector similarity |
| OpenSearch Serverless | Broad knowledge base, unstructured memory, high-concurrency agent writes | Scales write concurrency without Aurora connection limits |

**Required changes:**

1. Change `accounts.tf.json` contract from `"backend": "pgvector"` (single pick) to
   `"backends": ["pgvector", "opensearch"]` with per-backend configuration block.
   Bedrock KB remains a third option but for fully managed ingestion, not as a pgvector replacement.

2. **Tenant index isolation**: Add explicit requirement that each tenant gets:
   - A separate pgvector schema (e.g., `vectors_<tenant_id>`)
   - A separate OpenSearch index or collection
   Cross-tenant data contamination must be structurally impossible, not just IAM-controlled.

3. **Memory lifecycle**: Add short-term vs long-term memory distinction:
   - Short-term (sliding window): managed in compute state (not stored in vector DB)
   - Long-term (summarized episodes): stored in vector DB with TTL policy

**Severity:** High — blocks vector store Terraform if schema assumptions are wrong

---

### spec-09: ECS Fargate — EFS + Security Group Separation

**Source:** §1 Agentic Execution (Timeout Handling validation checklist)

**Current state:** spec-09 covers cluster, task definition, auto-scaling. No storage volume.

**Missing:**

1. **EFS persistent storage**: Fargate tasks must mount an EFS volume for mid-loop state
   (agent local variables, partial tool outputs) so if a container is recycled before completing
   a DynamoDB write, the next container can recover. The Terraform task definition must include
   an EFS volume declaration with access point per service.

2. **Security group split**: The VPC will contain both reasoning Lambda (spec-02) and execution
   sandbox Lambda (spec-12). These must have separate security groups with different egress rules.
   spec-09 should document its task security group separately from the sandbox security group.

**Severity:** Medium — EFS is a spec gap; security group split is a design clarification

---

### Dynamic IAM — New spec-15

**Source:** §4 Dynamic Blast Radius Control & IAM

**Current state:** The existing `workspaces/iam/` blueprint provisions static OIDC federated
roles (OIDC trust for HCP Terraform → AWS). No spec exists for runtime agent IAM.

**Missing entirely:**

The architecture requires a fundamentally different IAM model for running agents:

```
Static model (current):  Fargate/Lambda → one role → all permissions needed
Dynamic model (required): Fargate/Lambda → base role (minimal) →
                            STS AssumeRole w/ Session Policy (per tool call) →
                            Temporary credentials scoped to exact resource
```

spec-15 must document:
- **Base execution role**: Bedrock, DynamoDB (agent-state), SQS (ai-queue) only. Zero business data access.
- **Tool roles**: One IAM role per tool category (read-customer-data, write-order, send-email). Assumed dynamically.
- **Session policies**: Dynamic policies generated at runtime from user session context (customer ID, allowed data scope), passed to STS AssumeRole as inline policy.
- **Permissions Boundaries**: Attached to all agent execution roles. No privilege escalation possible even if session policy grants broad access.
- **No wildcard resources**: `*` resource is forbidden on any role accessible to agent frameworks. All resources must be named or use condition keys.

**Severity:** High — must be spec'd before any agent tool access to business data is implemented

---

## Existing Specs — Minor Updates Required

### spec-01: Bedrock — Throttling Alerts + KMS Prompt Logs

**Source:** §6 Model Governance, Safety & Observability

| Gap | Addition |
|-----|---------|
| Guardrails described as "content filtering" | Strengthen to "infrastructure-level proxy blocking prompt injection, PII, and toxic outputs before reaching application layer" |
| No throttling alerting | Add CloudWatch alarm on `ThrottledRequests` metric → SNS alert before agent failures occur |
| Prompt logging to S3 encryption not specified | Add requirement: customer-managed KMS key for all Bedrock invocation logs written to S3 |

---

### spec-04: AI Queue — DLQ Alerting + EventBridge Boundary

**Source:** §3 Asynchronous Message Mesh

| Gap | Addition |
|-----|---------|
| DLQs exist but no alert | Add CloudWatch alarm: DLQ `ApproximateNumberOfMessagesVisible` > 0 → SNS notification for stuck/looping agent detection |
| No boundary with EventBridge | Add section: "SQS handles task queuing (backpressure, delivery guarantee). EventBridge (spec-13) handles system event fan-out. Do not use SQS for event broadcasting." |
| FIFO queue purpose unclear | Clarify: FIFO is for HITL approval ordering and multi-agent sequential messaging. Not for high-throughput task dispatch (use standard queue for that). |

---

### spec-09: ECS — Minor additions alongside major EFS update

Already captured in major updates above.

---

### spec-10: AI Observability — X-Ray Sub-Segments + Mandatory Tags

**Source:** §6 Model Governance, Safety & Observability

| Gap | Addition |
|-----|---------|
| X-Ray mentioned but no field spec | Required sub-segment fields per agent invocation: `prompt_tokens`, `completion_tokens`, `latency_ms_per_step`, `model_tier`, `tool_calls_count`, `tool_call_names[]` |
| Bedrock RPM alerting absent | Add CloudWatch alarm on Bedrock `ThrottledRequests` (reference spec-01 alarm — may be same resource) |
| No mandatory tag requirement | Every trace span must include `TenantID`, `UserID`, `AgentID` as dimensions for per-agent cost attribution |
| KMS for Bedrock logs not mentioned | Bedrock invocation logs in S3 must use customer-managed KMS key from spec-01 output |

---

## Action Order

Execute in this sequence to unblock implementation:

```
1. spec-15-dynamic-iam       # Blocks all agent tool access to business data
2. spec-12-sandbox-lambda    # Blocks any agent code execution capability
3. spec-03 update            # Blocks DynamoDB Terraform (schema decisions)
4. spec-06 update            # Blocks vector store Terraform (dual-backend schema)
5. spec-00 update            # Add new blueprints to master catalog
6. spec-13-eventbridge       # Needed before HITL wiring
7. spec-14-realtime          # Needed before streaming UI
8. spec-09 update            # EFS (can be added at Phase B time if needed)
9. Minor: spec-01, spec-04, spec-10
```

---

## References

- [spec-00-ai-infra-overview.md](./spec-00-ai-infra-overview.md) — master ADR
- [spec-ca-review.md](./spec-ca-review.md) — Clean Architecture review (standard spec template)
- Architecture source: 6-section agentic infrastructure reference (2026-05-16)
