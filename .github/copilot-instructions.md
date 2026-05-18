---
description: Repo-wide conventions for Citadel Budgets work.
---

# Copilot Instructions — Citadel Budgets

This repo plans (and will host the fork of) **Citadel Budgets**, a per-user AI budget + reporting layer built on top of `Azure-Samples/ai-hub-gateway-solution-accelerator@citadel-v1`. See [AGENTS.md](../AGENTS.md) for project anchors. See [.github/prompts/plan-citadelBudgets.prompt.md](prompts/plan-citadelBudgets.prompt.md) for the canonical plan.

## Source of truth
- All architectural decisions live in the plan file. Do not introduce design changes in code without amending the plan first (use the [`update-plan`](prompts/update-plan.prompt.md) prompt).
- Phase numbering and decision IDs (D1–D6) are stable identifiers — preserve them.

## Naming & paths (must match upstream `citadel-v1`)
- IaC root is `bicep/infra/`. Never write `infra/` paths.
- Ingestion target is `src/usage-ingestion-logicapp/` (Logic App workflow JSON). Do not propose a C# Function.
- Validation notebooks live under `validation/` (e.g. `citadel-jwt-authentication-tests.ipynb`).
- Access Contracts live under `bicep/infra/citadel-access-contracts/`. Tier contracts go in `citadel-tiers/`, per-user overlays in `user-overrides/`.

## Anthropic specifics
- The API surface fronts `POST /v1/messages` (+ SSE streaming).
- Token usage fields are `usage.input_tokens` + `usage.output_tokens`. Map them to existing `promptTokens` / `responseTokens` / `totalTokens` Event Hub fields so PBIX + Logic App stay schema-compatible.
- Streaming: terminal `message_delta` event carries the final `usage.output_tokens`.

## Identity & auth
- APIM validates Entra JWT with `audience = {claude-code-app-id}` and `issuer = https://login.microsoftonline.com/{customer-tenant-id}/v2.0` (v2.0 issuer, never `sts.windows.net`).
- Strip the inbound user `Authorization` header before sending to Foundry. Use APIM managed identity for backend auth.
- Never assume `groups`/`roles` claims exist — they do not. Tier comes from the `user-tier` Cosmos container, populated by the tier-sync Function.
- For display, use `preferred_username`. For identity/joins, use `oid`. `upn` is null for guests.

## APIM policy conventions
- Reuse fragment patterns from `citadel-v1`: `frag-aad-auth.xml`, `frag-ai-usage.xml`, `frag-openai-usage-streaming.xml`.
- New fragments must be added to `bicep/infra/modules/apim/apim.bicep` alongside the existing fragment-registration block.
- Cache keys involving user data MUST include `oid` to prevent cross-user bleed.

## Budgets / Access Contracts
- Budgets are a **superset overlay** of Citadel Access Contracts, not a replacement.
- Tier contracts seed the `budgets` Cosmos container via deployment-script (see `_shared/budget-seed.bicep`).
- Precedence (locked): `(oid,model) → (oid,*) → (tier,model) → (tier,*) → global`.
- Enforcement headers: `x-citadel-budget-pct`, `x-citadel-budget-remaining`. 100% → HTTP 429 with `Retry-After` = seconds-until-next-month-UTC. `adminOverride=true` bypasses.

## Out of scope (POC)
Power App admin UI; Fabric migration; cost-based budgets; multi-region Cosmos DR; audit-log container (IaC commits are the audit trail).

## Style
- Be brief in docs. Tables > prose when comparing alternatives.
- Inline Bicep examples should be **illustrative** (not copy-paste-ready production code) — mark them as such.
- Every upstream link must point to `citadel-v1`, not `main`.
