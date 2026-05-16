# Spec-14: Real-Time Streaming (WebSocket)

**Status:** `[ ] not started`
**Phase:** Wave 2 — Client Connection Layer
**Default depends on:** `vpc`, `iam`, `spec-13-eventbridge` (HITL events), `spec-03-agent-state` (AWAITING_APPROVAL state reads)
**Blocks:** streaming agent responses to UI, HITL interruption in client
**Repo(s):** core-tfe-bootstrap-workspace-management

---

## Business Rule

Clients must receive agent execution updates (token output, tool calls, approval requests)
in real time without polling, and must be able to respond to HITL gates without a page reload
or connection restart.

---

## Goal

Provision a persistent WebSocket connection layer so the frontend receives:
1. Token-by-token streaming as the agent generates responses
2. Intermediate step updates (tool call started, tool result received)
3. HITL interruption — `AWAITING_APPROVAL` state pushed without client polling
4. Session completion or failure notification

Long agent sessions (10+ minutes) must remain connected without dropping. Client reconnection
must resume the session, not restart it (state is in DynamoDB spec-03, not the connection).

---

## Context

### Why WebSocket, Not SSE

Server-Sent Events (SSE) support unidirectional streaming from server to client. WebSocket
supports bidirectional — the client can send messages over the same connection (HITL approvals,
cancel requests, mid-session user messages). SSE requires a separate HTTP endpoint for client
messages, creating two connections that must be correlated.

WebSocket is preferred when:
- HITL approval response must travel back over the same channel
- User can send messages to a running agent (interrupt, redirect)
- Long-running sessions need ping/pong to stay alive

### Implementation Options

| Option | Cost | Fan-out | Ops overhead | HITL support |
|--------|------|---------|--------------|-------------|
| API Gateway WebSockets | Low | Custom (Lambda routes) | Medium | Yes |
| AWS AppSync Subscriptions | Higher | Managed GraphQL fan-out | Low | Yes |

Default: **API Gateway WebSockets** — lower cost, sufficient for single-tenant agent sessions.
AppSync is an upgrade path for multi-agent broadcast scenarios.

### Session Lifecycle

```
Client connects to wss://<domain>/ws?session_id=<id>
  → API Gateway WebSocket → Lambda $connect handler
  → $connect stores connectionId + session_id in DynamoDB connections table

Agent running (ECS / Lambda reasoning loop)
  → Calls spec-13 EventBridge: agent.step.completed
  → EventBridge → Lambda broadcast function
  → Lambda looks up connectionId for session_id
  → API Gateway Management API: PostToConnection(connectionId, payload)

Agent hits HITL gate
  → DynamoDB state = AWAITING_APPROVAL
  → EventBridge: agent.approval.required
  → Lambda pushes approval_required message to connectionId

Client approves in UI
  → Client sends message over WebSocket: { "type": "approval", "decision": "approve" }
  → $message Lambda handler → SQS HITL FIFO queue (spec-04)

Long session heartbeat
  → Client sends ping every 8 minutes (below 10-min API Gateway idle timeout)
  → Server responds pong
  → Connection stays alive for sessions up to hours
```

### Connection State Table

Requires a lightweight DynamoDB table for connection tracking (separate from agent-state):

```
Table: ws-connections
  PK: connectionId (string)
  SK: session_id (string)
  TTL: 24h (auto-expire stale connections)
  GSI: session_id → connectionId (look up by session)
```

This is provisioned by this blueprint, not spec-03 (different lifecycle, different access pattern).

---

## `accounts.tf.json` Contract

### Input Configuration (stable)

```json
"realtime": {
  "realtime_config_json": {
    "implementation": "apigateway-websocket",
    "stage_name": "prod",
    "idle_timeout_seconds": 600,
    "heartbeat_interval_seconds": 480,
    "connection_ttl_hours": 24,
    "routes": {
      "connect": { "enabled": true },
      "disconnect": { "enabled": true },
      "approval": { "enabled": true },
      "cancel": { "enabled": true },
      "default": { "enabled": true }
    },
    "logging": {
      "access_log_enabled": true,
      "execution_log_level": "ERROR"
    }
  }
}
```

### Implementation Notes (current)

- `implementation: apigateway-websocket` — API Gateway V2 WebSocket API
- Route Lambda functions: `$connect`, `$disconnect`, `$default`, plus named routes (`approval`, `cancel`)
- Connection tracking table: DynamoDB PAY_PER_REQUEST (provisioned by this blueprint)
- Broadcast Lambda invoked by EventBridge rule from spec-13 (not by client)
- `idle_timeout_seconds: 600` is the API Gateway maximum; client must send ping at `heartbeat_interval_seconds` to prevent disconnect

---

## Output Contract

| Output key | Type | Stability | Consumers |
|------------|------|-----------|-----------|
| `websocket_api_id` | string | stable | forge-core-ai (broadcast permission), DNS (custom domain) |
| `websocket_endpoint` | string | stable | agent-forge frontend env var |
| `websocket_stage_arn` | string | stable | IAM policy for PostToConnection |
| `connection_table_name` | string | stable | broadcast Lambda, spec-10 ai-obs |
| `broadcast_function_arn` | string | stable | spec-13 EventBridge target |

---

## Terraform Resources Created

- `aws_apigatewayv2_api` — WebSocket API
- `aws_apigatewayv2_stage` — deployment stage
- `aws_apigatewayv2_route` + `aws_apigatewayv2_integration` — per route ($connect, $disconnect, approval, cancel, $default)
- `aws_lambda_function` — route handlers + broadcast function
- `aws_iam_role` — Lambda execution role with `execute-api:ManageConnections` permission
- `aws_dynamodb_table` — connection tracking table (TTL enabled)
- `aws_cloudwatch_log_group` — access logs + execution logs

---

## Validation Checklist

From the architecture reference:

- [ ] **Connection idle timeout**: API Gateway WebSocket configured with 10-minute idle timeout. Client sends ping every 8 minutes. Long agent sessions (tested at 45 minutes) remain connected without manual reconnect.
- [ ] **HITL interruption**: `agent.approval.required` event received from EventBridge → WebSocket push to client within 1 second. Client UI shows approval prompt without reload.
- [ ] **Fan-out scalability**: Broadcast Lambda can invoke `PostToConnection` for 100+ concurrent sessions per agent run without throttling. Tested with concurrent broadcast load.
- [ ] **Reconnection**: If client disconnects and reconnects with same `session_id`, agent session resumes from DynamoDB state — agent does not restart.

---

## Tradeoffs

| Concern | Decision | Rationale |
|---------|----------|-----------|
| WebSocket vs SSE | WebSocket | Bidirectional required for HITL approval over same channel |
| API Gateway vs AppSync | API Gateway WebSocket | Lower cost at launch; AppSync upgrade path if GraphQL subscription model is needed |
| Connection state storage | DynamoDB (separate table) | Different TTL and access pattern from agent-state spec-03; kept separate to maintain SRP per spec |
| Broadcast trigger | EventBridge → Lambda | Decouples reasoning loop from knowing client connection details; EventBridge fan-out handles multiple consumers |

---

## References

- [spec-04-ai-queue.md](./spec-04-ai-queue.md) — SQS HITL FIFO queue receives approval decisions sent over WebSocket
- [spec-13-eventbridge.md](./spec-13-eventbridge.md) — Event source for broadcast trigger
- [spec-03-agent-state.md](./spec-03-agent-state.md) — AWAITING_APPROVAL state that triggers HITL push
- [spec-ca-review.md](./spec-ca-review.md) — Standard spec template reference
