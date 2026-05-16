# ADR 0005 — AI Infrastructure Blueprints for the Agency Platform

**Status:** proposed
**Date:** 2026-05-16
**Deciders:** platform engineering

---

## Context

The Agency platform currently deploys these blueprints per client via `accounts.tf.json`:

```
account-bootstrap → secure-baseline → vpc → rds → dns → waf → iam → secrets → lambda → api
```

This covers standard web-application infrastructure. It does not cover what AI-native companies
require: foundation model access, vector storage, agent state persistence, async task coordination,
and AI-specific observability.

Native AI companies (Decagon, Sierra, Cohere) structure their infrastructure around:

1. **Multi-model routing** — not one frontier model, but a tiered fleet (tiny triage model →
   specialized task models → powerful reasoning model). Cost scales with task complexity, not request count.
2. **RAG over fine-tuning** — knowledge bases stored in vector stores, injected dynamically.
   Fine-tuning is reserved for behavioral adaptation (tone, schema), not knowledge.
3. **Stateful agents** — conversation history and checkpoints persist across sessions.
   Agents resume, not restart.
4. **Async-first** — AI tasks decouple from API responses. Queues absorb spikes; HITL gates
   pause for human review without blocking the API.
5. **Cost-first observability** — token budget, cost per resolution, model latency p99, and
   resolution rate are first-class metrics, not afterthoughts.

This ADR introduces 10 new blueprints extending the existing catalog, designed to be:
- **Serverless-first**: $0 idle cost; Lambda and DynamoDB by default
- **Framework-agnostic**: LangGraph, PydanticAI, AutoGen, CrewAI all deploy without infra changes
- **Multi-backend**: vector store backend is selectable per client (pgvector / OpenSearch / Bedrock KB)
- **Agency-deployable**: any client opts in by adding services to their `accounts.tf.json` entry

---

## Decision

Add 10 new blueprints to the agency service catalog, deployable in 4 execution waves:

| Blueprint | Service key | Wave | Cost at zero traffic |
|---|---|---|---|
| Bedrock access | `bedrock` | 1 | ~$0 |
| Agent state (DynamoDB) | `agent-state` | 1 | ~$0 |
| Async queues (SQS) | `ai-queue` | 1 | ~$0 |
| AI storage (S3) | `ai-storage` | 1 | ~$0 |
| AI gateway (LiteLLM Lambda) | `ai-gateway` | 2 | ~$0 |
| Vector store | `vector-store` | 2 | ~$0 (pgvector) |
| Container registry (ECR) | `ecr` | 2 | ~$0.10/GB/month |
| Response cache (Redis) | `ai-cache` | 3 | ~$0 (serverless) |
| ECS Fargate runtime | `ecs` | 3 | ~$30/service/month |
| AI observability | `ai-obs` | 4 | ~$1/month |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  CONTROL PLANE — accounts.tf.json + HCP Terraform                               │
│  One line adds any AI service to any client environment                         │
└────────────────────────────────┬────────────────────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────────────────────┐
│  FOUNDATION (existing — no changes)                                             │
│  account-bootstrap → secure-baseline → vpc → rds → iam → secrets → api         │
└────────────────────────────────┬────────────────────────────────────────────────┘
                                 │
         ┌───────────────────────┼────────────────────────────┐
         ▼                       ▼                            ▼
┌────────────────┐   ┌───────────────────────┐   ┌───────────────────────────────┐
│  WAVE 1        │   │  WAVE 2               │   │  WAVE 3 / 4                   │
│  (serverless,  │   │  (model access +      │   │  (scale + observability)      │
│   parallel)    │   │   knowledge)          │   │                               │
│                │   │                       │   │  ┌──────────────────────────┐ │
│  spec-01       │   │  spec-02              │   │  │  spec-08: ai-cache       │ │
│  bedrock       │──▶│  ai-gateway           │   │  │  ElastiCache Serverless  │ │
│  (IAM +        │   │  LiteLLM Lambda proxy │   │  └──────────────────────────┘ │
│   VPC endpoint │   │  → ECS at scale       │   │                               │
│   + Guardrails)│   │  → AgentCore swap     │   │  ┌──────────────────────────┐ │
│                │   │                       │   │  │  spec-09: ecs            │ │
│  spec-03       │   │  spec-06              │   │  │  ECS Fargate cluster     │ │
│  agent-state   │   │  vector-store         │   │  │  (Phase B when Lambda    │ │
│  DynamoDB      │   │  pgvector |           │   │  │   limits hit)            │ │
│  checkpoints   │   │  OpenSearch |         │   │  └──────────────────────────┘ │
│  + memory      │   │  Bedrock KB           │   │                               │
│                │   │                       │   │  ┌──────────────────────────┐ │
│  spec-04       │   │  spec-07              │   │  │  spec-10: ai-obs         │ │
│  ai-queue      │   │  ecr                  │   │  │  CloudWatch dashboards   │ │
│  SQS tasks +   │   │  Container registry   │   │  │  X-Ray traces            │ │
│  HITL FIFO     │   │  (framework lives     │   │  │  Cost alarms             │ │
│                │   │   here, not infra)    │   │  └──────────────────────────┘ │
│  spec-05       │   │                       │   │                               │
│  ai-storage    │   │                       │   └───────────────────────────────┘
│  S3: training  │   │                       │
│  + artifacts   │   │                       │
└────────────────┘   └───────────────────────┘


Framework-agnostic contract:
  Infrastructure exposes → endpoints, ARNs, table names, queue URLs
  Framework lives in    → Docker image (ECR)
  Swap LangGraph for PydanticAI = push new image, zero infra change
  Swap LiteLLM for AgentCore   = change ai_gateway.runtime, zero infra change
```

---

## Execution Dependency Map

Dependencies are resolved by HCP Terraform workspace `depends_on` chains.
Items within the same wave can be applied in parallel.

```
Wave 0 — Foundation (existing, must be applied first)
  account-bootstrap
    └── secure-baseline
          └── vpc
                ├── rds
                ├── iam
                └── secrets

Wave 1 — Serverless AI Foundations (parallel within wave)
  spec-01: bedrock      requires: vpc (VPC endpoint), iam
  spec-03: agent-state  requires: iam only
  spec-04: ai-queue     requires: iam only
  spec-05: ai-storage   requires: iam, secure-baseline (KMS key)

Wave 2 — Model Access + Knowledge (parallel within wave)
  spec-02: ai-gateway   requires: spec-01 (bedrock), secrets, iam
  spec-06: vector-store requires: vpc + rds (pgvector) OR vpc (opensearch) OR bedrock (kb)
  spec-07: ecr          requires: iam

Wave 3 — Caching + Scale Compute (parallel within wave)
  spec-08: ai-cache     requires: vpc, secrets
  spec-09: ecs          requires: vpc, spec-07 (ecr), secrets, iam, spec-01 (bedrock)

Wave 4 — Observability (after all prior waves)
  spec-10: ai-obs       requires: iam, all prior blueprints deployed
```

---

## New Services in `accounts.tf.json`

Clients add AI blueprints by extending their `services` array. Order does not matter —
dependency resolution happens in HCP Terraform workspace dependency chains.

```json
"services": [
  "account-bootstrap",
  "secure-baseline",
  "vpc",
  "rds",
  "dns",
  "waf",
  "iam",
  "secrets",
  "api",
  "bedrock",
  "agent-state",
  "ai-queue",
  "ai-storage",
  "ai-gateway",
  "vector-store",
  "ecr",
  "ai-cache",
  "ecs",
  "ai-obs"
]
```

Clients can opt into any subset. `ai-gateway` requires `bedrock`. `ecs` requires `ecr`.
All other AI blueprints are independently deployable after Wave 0.

---

## Framework-Agnostic Contract

The infrastructure never imports framework-specific config. Every blueprint exposes
generic AWS primitives:

| Blueprint output | Frameworks that consume it |
|---|---|
| `bedrock.bedrock_role_arn` | Any AWS SDK caller (boto3, bedrock-runtime client) |
| `bedrock.guardrail_ids` | Any Bedrock API caller |
| `ai_gateway.endpoint_url` | LangGraph, PydanticAI, AutoGen — any OpenAI-compat API client |
| `agent_state.checkpoints_table_name` | LangGraph checkpointer, PydanticAI state, custom adapters |
| `agent_state.memory_table_name` | LangMem, custom memory implementations |
| `ai_queue.tasks_queue_url` | Any async worker polling SQS |
| `ai_queue.hitl_queue_url` | Any HITL gate implementation |
| `vector_store.endpoint` | LangChain retriever, LlamaIndex, custom RAG |
| `ecr.repository_urls` | Docker push from CI; Docker pull by ECS tasks |
| `ai_cache.endpoint` | Any Redis client (semantic cache, session cache) |

**The AI framework (LangGraph, PydanticAI, etc.) lives inside the Docker image stored in ECR.**
The Terraform blueprints provision the runtime environment, not the framework.

---

## Implementation Waves Detail

### Wave 1: Serverless AI Foundations

All four blueprints are independent of each other. Apply in parallel after Wave 0.

| Spec | Blueprint | What it creates |
|---|---|---|
| spec-01 | `bedrock` | IAM invoke policy, VPC interface endpoint, Guardrails, invocation log group, inference profiles |
| spec-03 | `agent-state` | DynamoDB tables: `agent-checkpoints` (TTL 30d, streams) + `agent-memory` (TTL 90d, PITR) |
| spec-04 | `ai-queue` | SQS standard task queue + SQS FIFO HITL queue + DLQs for both |
| spec-05 | `ai-storage` | S3 buckets: training-data, model-artifacts, adapter-weights, eval-datasets |

Cost at zero traffic: **~$0/month** (DynamoDB PAY_PER_REQUEST, SQS per-message billing)

### Wave 2: Model Access + Knowledge

| Spec | Blueprint | What it creates | Key dependency |
|---|---|---|---|
| spec-02 | `ai-gateway` | Lambda function URL running LiteLLM proxy | spec-01 (bedrock) |
| spec-06 | `vector-store` | pgvector extension OR OpenSearch Serverless collection OR Bedrock KB | vpc + rds OR bedrock |
| spec-07 | `ecr` | ECR repositories per service type, scan policy, lifecycle policy | iam |

Cost at zero traffic: **~$0-5/month** (Lambda pay-per-call, ECR ~$0.10/GB)

### Wave 3: Caching + Scale Compute

| Spec | Blueprint | What it creates | Key dependency |
|---|---|---|---|
| spec-08 | `ai-cache` | ElastiCache Serverless Redis cluster | vpc, secrets |
| spec-09 | `ecs` | ECS cluster + Fargate task definitions + auto-scaling | vpc, ecr, bedrock |

Note: `spec-09 ecs` is **optional** at launch. Only required when Lambda cold-start latency
is unacceptable OR orchestrators exceed the 15-minute Lambda timeout. Add when scale demands it.

Cost: `ai-cache` ~$0 serverless idle; `ecs` ~$30-50/service/month when running.

### Wave 4: Observability

| Spec | Blueprint | What it creates |
|---|---|---|
| spec-10 | `ai-obs` | CloudWatch log groups, dashboards, alarms, X-Ray group, custom metric namespace |

Cost: **~$1-5/month** (CloudWatch log ingestion + dashboard charges)

---

## Tradeoffs

| Concern | Decision | Rationale |
|---|---|---|
| Vector store backend | Multi-backend (pgvector / OpenSearch / Bedrock KB) selectable via config | Different clients have different scale and cost requirements; one schema handles all |
| AI gateway runtime | Lambda first, ECS second | Lambda = $0 idle; ECS adds $30-50/service/month — don't pay for it until needed |
| Model provider | Multi-provider (Bedrock primary, Anthropic direct fallback) | Bedrock gives VPC private access + inference profiles; direct API is fallback for models not on Bedrock |
| ECS tenancy | One cluster per client environment | Tenant isolation; shared cluster would reduce blast radius separation |
| Fine-tuning | Storage only (S3 buckets) now; SageMaker deferred | Fine-tuning need unvalidated; storage foundations cost nothing and unblock future spec |
| Bedrock AgentCore | Noted as future swap for ai-gateway + agent-state | AgentCore is a managed runtime that could replace 3 blueprints; evaluate after launch |

---

## Consequences

- Any client can enable world-class AI infrastructure with one `accounts.tf.json` change
- `ai-gateway` provides a stable internal endpoint — AI frameworks call one URL, never provider APIs directly
- All AI calls are private (VPC endpoint to Bedrock) — no internet egress for model calls
- Token usage, cost, and latency are observable from day one via `ai-obs`
- Adding a new AI framework = push a Docker image; zero infra change
- Swapping the model provider = update `ai_gateway_config_json.providers`; zero framework change

---

## Post-MVP / Future Specs

These are explicitly deferred and will become separate spec files:

| Future spec | What it covers |
|---|---|
| [spec-11: Fine-tuning pipeline](./spec-11-fine-tuning.md) | SageMaker training jobs, LoRA adapter management, model registry, training pipeline via Step Functions. **Prereq:** spec-05 deployed + base RAG validated. |
| Bedrock AgentCore evaluation | Comparison vs LiteLLM proxy — managed runtime replacing ai-gateway + agent-state + ai-obs |
| Multi-region AI | Global DynamoDB tables, Bedrock cross-region inference profiles, multi-region ECS |
| Bedrock Flows | Visual workflow builder for no-code agent orchestration |
| EventBridge Pipes | SQS → Lambda/ECS triggers for event-driven AI pipelines |
| Cost anomaly detection | AWS Cost Anomaly Detection per service + per tenant attribution |
| AWS Step Functions | Complex multi-agent orchestration with built-in retries and branching |

---

## References

- [Agency-Orchestration-Platform-Spec.md](../Agency-Orchestration-Platform-Spec.md) — existing control plane spec
- [spec-01-bedrock.md](./spec-01-bedrock.md)
- [spec-02-ai-gateway.md](./spec-02-ai-gateway.md)
- [spec-03-agent-state.md](./spec-03-agent-state.md)
- [spec-04-ai-queue.md](./spec-04-ai-queue.md)
- [spec-05-ai-storage.md](./spec-05-ai-storage.md)
- [spec-06-vector-store.md](./spec-06-vector-store.md)
- [spec-07-ecr.md](./spec-07-ecr.md)
- [spec-08-ai-cache.md](./spec-08-ai-cache.md)
- [spec-09-ecs.md](./spec-09-ecs.md)
- [spec-10-ai-obs.md](./spec-10-ai-obs.md)
- [spec-11-fine-tuning.md](./spec-11-fine-tuning.md) — Post-MVP: LoRA/QLoRA fine-tuning pipeline (SageMaker + Step Functions)
