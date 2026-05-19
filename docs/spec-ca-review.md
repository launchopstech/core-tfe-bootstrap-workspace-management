# ADR — Clean Architecture Review: AI Infrastructure Blueprints

**Status:** active
**Date:** 2026-05-16
**Deciders:** platform engineering
**Scope:** `docs/spec-00` through `docs/spec-11`

---

## Overall Score: 7/10

The AI blueprint specs demonstrate strong instincts at the system level — the framework-agnostic
output contract in spec-00, the wave model's alignment with stable-dependencies-first ordering,
and the `accounts.tf.json` as a single clean input boundary are all genuine Clean Architecture
wins. The Dependency Rule is followed at the macro level.

The score is held at 7 by three structural gaps that compound across every spec: (1) no spec has
an explicit **Output Port** section separating its stable interface from its implementation details,
making it unclear what downstream specs can depend on safely; (2) two specs let outer-circle
names (LiteLLM, DynamoDBSaver, SageMaker) appear in inner-circle spec language; and (3) spec-06's
conditional dependency graph breaks ADP clarity.

Addressing these gaps does not require rewriting the specs — it requires adding structure to the
existing content.

---

## CA Layer Mapping for this IaC System

Clean Architecture's four concentric circles translate directly to the control plane:

| CA Circle | This System |
|-----------|-------------|
| **Entities** (enterprise business rules) | Platform invariants: "agents must resume not restart", "all model calls must be private", "multi-tenant isolation enforced at key construction, not just IAM policy", "AI framework must be swappable without infra change" |
| **Use Cases** (application business rules) | Blueprint contracts: the Input Contract (`accounts.tf.json` config per service) + the Output Port (Terraform outputs consumed by downstream blueprints and AI frameworks) |
| **Interface Adapters** | `modules/aws/` Terraform modules: translate Use Case contracts into AWS-specific resource declarations. `workspaces/` roots: wire modules together and publish outputs. |
| **Frameworks & Drivers** | AWS services (DynamoDB, SQS, Bedrock, ElastiCache), HCP Terraform provider, LiteLLM container image, specific AWS SDK versions, Python EMF library |

**The Dependency Rule for IaC**: A blueprint spec (Use Case) must never name a specific AWS service
class, a specific framework library, or a specific tool in its stable output contract. It may name
these in implementation detail sections. The `modules/aws/` layer (Interface Adapters) is allowed
— and expected — to name specific AWS resources. The `workspaces/` roots are the composition
layer that wires adapters together.

```
accounts.tf.json (Input Port)
  → accounts/main.tf (Use Case: validates + creates workspace)
    → workspaces/<blueprint>/main.tf (Use Case: declares outputs)
      → modules/aws/<service>/ (Interface Adapter: AWS-specific resources)
        → AWS Provider / HCP Terraform Provider (Framework Driver)
```

---

## Quick Diagnostic Results

| Question | Result | Note |
|----------|--------|------|
| Can business rules be read without knowing the AWS implementation? | **Partial** | spec-00 goal section yes; individual spec context sections mix levels |
| Do source code dependencies point inward on every import? | **Yes** | No module calls an outer-circle module; wave ordering is correct |
| Can the vector store backend be swapped without changing AI framework code? | **Yes** | spec-06 uniform output contract guarantees this |
| Are Use Case output contracts independent of the delivery mechanism? | **Partial** | spec-00 has the contract table; individual specs lack Output Port sections |
| Are Frameworks (LiteLLM, DynamoDBSaver) confined to outermost descriptions? | **Partial** | spec-02 and spec-03 name frameworks in inner-circle language |
| Can the dependency graph be confirmed acyclic? | **Partial** | Waves 0-4 are acyclic; spec-06's conditional deps are ambiguous |
| Does a composition root wire all dependencies at startup? | **Yes** | `workspaces/account-portal` is the composition root that creates all child workspaces |

---

## Per-Principle Analysis

### 1. Dependency Rule

**Score: 8/10**

The rule is followed at the macro level. The spec-00 Framework-Agnostic Contract table is a
textbook example: inner-circle specs expose generic primitives (ARNs, URLs, table names) that
any outer-circle consumer can use regardless of framework choice.

**Violations:**

`spec-02 ai-gateway` — The Input Contract section includes LiteLLM-specific YAML fields
(`model_list`, `litellm_settings`, `router_settings`, `general_settings`). These are outer-circle
configuration details for a specific implementation (LiteLLM). A client configuring the gateway
should specify *what they need* (`providers`, `model_tiers`, `rate_limits`) not *how LiteLLM
implements it*. If LiteLLM is replaced with Bedrock AgentCore, the Input Contract should not
need to change.

`spec-03 agent-state` — The context section names `LangGraph nodes`, `LangGraph DynamoDBSaver`,
and `PydanticAI steps` as examples of what the tables store. These are outer-circle names appearing
in an inner-circle spec. The spec correctly notes "framework-agnostic" but then illustrates the
contract using framework-specific terminology. The partition key design (`tenant_id#session_id`)
is a genuine business rule and belongs here. The framework names do not.

**Fix:** In spec-02, split the Input Contract into `Gateway Configuration` (framework-agnostic:
providers, tiers, routing strategy) and `Implementation Notes` (LiteLLM YAML reference). In
spec-03, replace "LangGraph nodes, PydanticAI steps" with "execution snapshots" and move the
framework-specific examples to an Implementation Notes footnote.

---

### 2. Entities and Use Cases

**Score: 7/10**

The system's Entities (platform business rules) are mostly implicit. They can be inferred from
the spec Goals and Context sections, but they are not explicitly separated from Use Case rules
(how the blueprint orchestrates those rules into deployable infrastructure).

**Examples of Entity-level rules that should be explicit:**
- "All model invocations must route privately through the client VPC" — this is an enterprise
  rule (would exist even without Terraform). spec-01 states it as "VPC endpoint required" which
  blurs it with the implementation (the VPC endpoint is the mechanism, not the rule).
- "Agent execution must be resumable, not restartable" — stated in spec-03 context as a pattern
  choice but is actually an enterprise invariant.
- "Multi-tenant data isolation must be enforced at key construction, not only at IAM policy level"
  — buried in spec-03 context; this is a critical enterprise rule.

**Use Case rules (specific to this application) are well defined:**
- Each blueprint's dependency declarations define what the Use Case requires
- Input Contracts define what clients configure
- Outputs define what the Use Case delivers

**Fix:** Add a `## Business Rule` (or `## Why This Exists`) sub-section to each spec that
states the one-sentence invariant the blueprint enforces. This separates the Entity-level
concern from the Use Case implementation.

---

### 3. Interface Adapters and Frameworks

**Score: 8/10**

The architecture correctly treats AWS as a detail. The `modules/aws/` layer is the Interface
Adapter that translates blueprint contracts into provider-specific resources. The `workspaces/`
roots are thin composition layers that wire modules together.

**Strengths:**
- spec-07 ECR explicitly states "To swap frameworks: build new image, push, no Terraform change"
- spec-09 ECS "Framework-agnostic: ECS task definition references ECR image URL"
- spec-08 Cache: "The cache is advisory — AI frameworks gracefully degrade if Redis is unreachable"

**Minor violations:**

`spec-05 ai-storage` — Names "LiteLLM adapter loading" as a processing pipeline. This is an
outer-circle implementation detail appearing in an inner-circle spec. The spec should say
"adapter loading pipeline" without naming the loader.

`spec-08 ai-cache` — Notes "This is configured in LiteLLM's config.yaml". This is correct
(LiteLLM config is an outer-circle detail) but the sentence places a Framework Driver detail
in a Use Case spec's context section. Should be moved to an Implementation Notes section.

`spec-10 ai-obs` — Includes a Python code snippet using `@metric_scope` from
`aws_embedded_metrics`. As an illustration of EMF it is useful; as spec content it blurs the
boundary. The Terraform blueprint's contract is the log group name and metric namespace — not
the application-side emit pattern. Move the Python example to a "How services should emit"
appendix, clearly labeled as guidance for outer-circle consumers.

---

### 4. Component Principles

**Score: 7/10**

**Acyclic Dependencies (ADP) — Partial violation in spec-06:**

spec-06 vector-store's `Depends on` header reads:
```
vpc, rds (pgvector backend), spec-01-bedrock (bedrock-kb backend),
spec-05-ai-storage (knowledge_docs bucket for bedrock-kb), iam
```

This lists three mutually exclusive dependency sets as simultaneous. The actual dependency
graph of this component varies depending on which backend is selected:
- `pgvector` requires: `vpc`, `rds`, `iam`
- `opensearch-serverless` requires: `vpc`, `iam`
- `bedrock-kb` requires: `spec-01-bedrock`, `spec-05-ai-storage`, `iam`

A component whose dependency graph is non-deterministic without runtime config cannot be
statically verified to be acyclic. This is not a cycle per se, but it is an ADP clarity violation
that makes workspace dependency chains impossible to pre-validate.

**Stable Dependencies (SDP) — Well aligned:**

The wave model naturally implements SDP. Components in Wave 0 (secure-baseline, vpc, rds) are
highly stable — many components depend on them, they depend on few others. Components in Wave 3
(ecs, ai-cache) are volatile — they depend on many components and few components depend on them.
This is the correct direction.

**Reuse/Release Equivalence (REP) — Appropriate:**

Each blueprint is independently releasable via `accounts.tf.json` opt-in. The `modules/aws/`
layer modules are versioned together in this repo, which is correct — they change for the same
reasons (AWS provider updates, security policy changes).

**Fix for spec-06:** Replace the merged `Depends on` header with a `Backend Dependency Map`:

```
Backend         | Requires
----------------|--------------------------------------------
pgvector        | vpc, rds, iam
opensearch      | vpc, iam
bedrock-kb      | spec-01-bedrock, spec-05-ai-storage, iam
```

The `Depends on` header should list only the dependencies of the *default backend* (pgvector)
since that is what most clients will use. Conditional dependencies belong in a named sub-section.

---

### 5. Boundaries and Boundary Anatomy

**Score: 6/10** — This is the primary gap across all specs.

Every spec has a well-defined **Input Port** (`accounts.tf.json` contract) but no spec has an
explicit **Output Port** section. The stable outputs are documented in spec-00's Framework-Agnostic
Contract table, but not in the individual spec files.

This matters because:
- Downstream specs (and downstream engineers) cannot determine what is a stable contract vs.
  what is an implementation detail that may change
- When spec-09 ECS needs the checkpoints table name from spec-03, there is no canonical place
  in spec-03 to verify that `agent_state.checkpoints_table_name` is the stable output key
- New specs have no template to follow for declaring their output boundary

**No spec separates:**
1. Stable output contract (what downstream components can depend on — must not break)
2. Convenience outputs (available but may change without notice)
3. Implementation details (internal resource names, IDs not consumed by others)

**Fix:** Add an `## Output Contract` section to each spec (see template below).

---

### 6. SOLID Principles (as applied to IaC spec design)

**Score: 7/10**

SOLID principles apply to spec design as a form of module design:

**SRP** — Each spec has one reason to change. spec-01 changes when Bedrock access policy
changes. spec-07 changes when container registry policy changes. This is well-maintained.
Exception: spec-09 ECS covers both the cluster/task definition and the auto-scaling configuration
— these could split but the coupling is justified at this stage.

**OCP** — The `accounts.tf.json` pattern is open for extension (add a service key) without
modifying existing entries. New AI blueprints extend the catalog without touching existing
blueprint specs.

**ISP** — Each blueprint exposes only what it owns. spec-01 bedrock does not include IAM
role creation — that is spec `iam`. spec-03 agent-state does not include encryption — that
comes from the variable set. Interface segregation is well applied.

**DIP** — spec-02 ai-gateway depends on spec-01 bedrock via a Terraform output reference,
not a hardcoded ARN. This is the Dependency Inversion mechanism for IaC. It is correctly
applied across all wave dependencies.

---

## Per-Spec Violations Summary

| Spec | Severity | Violation | Fix |
|------|----------|-----------|-----|
| spec-00 | Low | Wave model lacks stability ratios; no signal which outputs are load-bearing contracts | Add output stability annotation (`stable` / `convenience`) to Framework-Agnostic Contract table |
| spec-01 | Low | "VPC interface endpoint required" is implementation detail stated as business rule | Separate: business rule = "private model invocation"; implementation = VPC endpoint |
| spec-01 | Medium | No Output Port section | Add `## Output Contract` section |
| spec-02 | High | LiteLLM YAML (`model_list`, `litellm_settings`) in Input Contract | Split Input Contract into `Gateway Configuration` (stable) + `Implementation Notes: LiteLLM` (swappable) |
| spec-02 | Medium | No Output Port section | Add `## Output Contract` section |
| spec-03 | Medium | "LangGraph nodes", "DynamoDBSaver", "PydanticAI steps" named in spec context | Replace with "execution snapshots"; move framework names to Implementation Notes |
| spec-03 | Medium | No Output Port section | Add `## Output Contract` section |
| spec-04 | Low | No Output Port section | Add `## Output Contract` section |
| spec-05 | Low | "LiteLLM adapter loading" named in implementation context | Replace with "adapter loading pipeline" |
| spec-05 | Medium | No Output Port section | Add `## Output Contract` section |
| spec-06 | High | Conditional dependency graph in `Depends on` header violates ADP clarity | Replace with Backend Dependency Map table |
| spec-06 | Medium | No Output Port section | Add `## Output Contract` section (already implied by uniform output statement) |
| spec-07 | Low | No Output Port section | Add `## Output Contract` section |
| spec-08 | Low | "LiteLLM's config.yaml" named in Use Case context | Move to Implementation Notes |
| spec-08 | Medium | No Output Port section | Add `## Output Contract` section |
| spec-09 | Low | No Output Port section | Add `## Output Contract` section |
| spec-10 | Low | Python `@metric_scope` code snippet in spec body | Move to appendix labeled "How AI services emit metrics (guidance for outer-circle consumers)" |
| spec-10 | Medium | No Output Port section | Add `## Output Contract` section |
| spec-11 | Low | No Output Port section | Add `## Output Contract` section |

---

## Priority Improvements

Ordered by impact on downstream clarity and implementation safety:

### P1 — Add Output Contract sections to Wave 1 specs (highest leverage)

Wave 1 specs (spec-01, spec-03, spec-04, spec-05) are consumed by Wave 2 and Wave 3 blueprints.
Without explicit output contracts, each downstream spec author must infer what is safe to depend on.

Minimum Output Contract content per spec:

```markdown
## Output Contract

| Output key | Type | Stability | Consumers |
|------------|------|-----------|-----------|
| `checkpoints_table_name` | string | stable | spec-09-ecs, forge-core-ai |
| `checkpoints_table_arn` | string | stable | iam policy bindings |
| `memory_table_name` | string | stable | spec-09-ecs, forge-core-ai |
| `memory_table_arn` | string | stable | iam policy bindings |
| `checkpoints_stream_arn` | string | convenience | event-driven consumers |

**Stability definitions:**
- `stable` — part of the blueprint's public interface; will not change without a deprecation notice
- `convenience` — available but may be renamed or removed without notice
```

### P2 — Fix spec-02 ai-gateway Input Contract

The Input Contract currently includes LiteLLM-specific fields. Split into two sections:

**Gateway Configuration (stable — survives an LiteLLM → AgentCore swap):**
- `providers`: array of provider configs (name, credentials reference, priority)
- `model_tiers`: mapping of `fast | balanced | powerful` to model IDs
- `rate_limits`: per-tenant RPM/TPM limits
- `runtime`: `lambda | ecs` (compute backend choice)
- `cache`: Redis integration on/off (not LiteLLM-specific config)

**Implementation Notes: LiteLLM (current runtime):**
- The LiteLLM `config.yaml` structure, `model_list` format, and `litellm_settings` go here
- Label this section: "These fields are implementation details for the current Lambda runtime.
  If the gateway runtime changes, this section changes. The Gateway Configuration above does not."

### P3 — Fix spec-06 vector-store dependency declaration

Replace:
```
**Depends on:** vpc, rds (pgvector backend), spec-01-bedrock (bedrock-kb backend),
spec-05-ai-storage (knowledge_docs bucket for bedrock-kb), iam
```

With:
```
**Default depends on (pgvector):** vpc, rds, iam

**Backend dependency map:**
| Backend              | Requires                                      |
|----------------------|-----------------------------------------------|
| pgvector (default)   | vpc, rds, iam                                 |
| opensearch-serverless| vpc, iam                                      |
| bedrock-kb           | spec-01-bedrock, spec-05-ai-storage, iam      |
```

This makes the dependency graph deterministic for any given client configuration.

### P4 — Add Business Rule preamble to each spec

Before the `## Goal` section, add a one-sentence `## Business Rule` that states the
invariant the blueprint enforces at the Entity level. Examples:

- spec-01: "All model invocations from this client environment must route privately through the client VPC and be subject to content controls."
- spec-03: "Agent execution state must persist across compute restarts so agents resume at their last checkpoint rather than starting over."
- spec-06: "The platform's knowledge retrieval interface must be backend-agnostic so clients can scale from relational to dedicated vector infrastructure without changing AI framework code."

This separates the reason the blueprint exists (Entity rule) from what it creates (Use Case).

---

## Standard Spec Template

Use this structure for new AI blueprint specs and when revising existing ones:

```markdown
# Spec-NN: <Blueprint Name>

**Status:** `[ ] not started | [x] complete`
**Phase:** Wave N — <Wave Name>
**Default depends on:** <comma-separated service keys for the default config>
**Blocks:** <downstream specs that cannot proceed until this one is applied>
**Repo(s):** core-tfe-bootstrap-workspace-management

---

## Business Rule

<One sentence: the enterprise invariant this blueprint enforces. Should be true even if
the cloud provider, Terraform, and all framework choices change.>

---

## Goal

<What this blueprint deploys. Use generic terms. Do not name specific AWS resources here.>

---

## Context

<Why this is needed, design decisions, and tradeoffs. May reference specific AWS services
and framework tools as examples of how the contract is consumed — label these as examples,
not contracts.>

<If the spec has conditional dependencies (multiple backends), include a Backend Dependency
Map here instead of in the header.>

---

## `accounts.tf.json` Contract

### Input Configuration (stable)
<Fields that define WHAT the client needs. Must not name specific implementation tools.>

### Implementation Notes (current)
<How the current Terraform implementation interprets the Input Configuration. This section
changes when the implementation changes. The Input Configuration above does not.>

---

## Output Contract

| Output key | Type | Stability | Consumers |
|------------|------|-----------|-----------|
| `<key>` | string | stable | <who reads this output> |
| `<key>` | string | convenience | <who reads this output> |

**Stability definitions:**
- `stable` — part of the blueprint's public interface; will not change without a deprecation notice
- `convenience` — available but may be renamed or removed without notice

---

## Terraform Resources Created

<Bulleted list of resource types created. This is the Interface Adapter section —
naming specific AWS resource types is appropriate here.>

---

## Tradeoffs

<Decision table: concern → choice → rationale.>
```

---

## Verification

When applying these improvements to an individual spec:

1. **Dependency Rule check**: Read the Input Configuration section. If any sentence names a
   specific framework library (LiteLLM, LangGraph, DynamoDBSaver) or specific SDK version,
   move it to Implementation Notes.

2. **Output Port check**: Every output that another spec's `Depends on` header references must
   appear in the Output Contract table with a `stable` annotation.

3. **ADP check**: If the spec has conditional dependencies (different backends, optional
   integrations), replace the merged `Depends on` header with a Backend Dependency Map table.
   The `Depends on` header should list only the minimum required dependencies for the default
   configuration.

4. **Entity check**: The Business Rule section should be true without Terraform, without AWS,
   and without any specific framework. If it references a cloud resource, it is a Use Case rule,
   not a Business Rule.

5. **Score reassessment**: After applying P1-P4 above, the expected score improves to **9/10**.
   The remaining gap (1 point) closes when the `modules/aws/bedrock/`, `modules/aws/agent-state/`
   etc. Terraform modules are implemented and their output declarations match the Output Contract
   tables.

---

## References

- [spec-00-ai-infra-overview.md](./spec-00-ai-infra-overview.md) — master ADR and framework-agnostic contract
- [Agency-Orchestration-Platform-Spec.md](../Agency-Orchestration-Platform-Spec.md) — control plane architecture
- [Clean Architecture (Robert C. Martin)](https://www.amazon.com/Clean-Architecture-Craftsmans-Software-Structure/dp/0134494164) — foundational reference
