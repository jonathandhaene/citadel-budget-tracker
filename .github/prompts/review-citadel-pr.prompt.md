---
mode: agent
description: Review a Citadel PR (or local diff) against the plan, locked decisions, and conventions.
---

# Review Citadel PR

Target: **${input:target:PR URL or "current diff"}**

## Checklist

### Plan alignment
- [ ] Does the diff implement a phase that exists in the plan? Cite the phase.
- [ ] Does it contradict any locked decision (D1–D6)? If yes — **block** and route to citadel-architect.
- [ ] Does it require a new Adjustments-table row? If yes — block until the plan is amended.

### Paths & naming
- [ ] All IaC under `bicep/infra/` (no stray `infra/`).
- [ ] Ingestion changes touch `src/usage-ingestion-logicapp/` (not a Function).
- [ ] Access Contracts under `bicep/infra/citadel-access-contracts/`.
- [ ] New Cosmos containers match the schema: `ai-usage-monthly` (PK `/oid`), `budgets` (PK `/scope`), `user-tier` (PK `/oid`).

### APIM policies
- [ ] JWT audience is parameterized (Claude Code app id). Issuer uses v2.0 (`/v2.0` suffix).
- [ ] Inbound `Authorization` is stripped before backend call.
- [ ] Cache keys touching user data include `oid`.
- [ ] Streaming captures `usage.output_tokens` from terminal `message_delta`.
- [ ] 100% block returns HTTP 429 with `Retry-After`. `adminOverride` bypass present.
- [ ] Soft headers `x-citadel-budget-pct` / `x-citadel-budget-remaining` set on warn.

### Bicep
- [ ] Module reused where one exists (AVM or citadel-v1 module).
- [ ] No secrets in outputs.
- [ ] Managed identity used for backend auth.

### Validation
- [ ] New behavior has a corresponding cell in a `validation/*.ipynb`.
- [ ] Cells use assertions, not prints.
- [ ] No real tokens committed.

### Docs
- [ ] Upstream links point to `citadel-v1`, never `main`.
- [ ] Inline Bicep in markdown is marked illustrative.

## Output
- One of: **APPROVE** / **REQUEST CHANGES** / **BLOCKED ON PLAN AMENDMENT**.
- A bullet list of failing checks (if any) with file:line citations.
