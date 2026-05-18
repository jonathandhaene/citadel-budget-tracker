# Citadel Budgets — Repo Memory

This repo is the planning + (eventually) fork home of **Citadel Budgets**: per-user AI token budgets and reporting for Claude Code (Anthropic) on Microsoft Foundry, built as a fork of **`Azure-Samples/ai-hub-gateway-solution-accelerator` branch `citadel-v1`** (the reference implementation of Layer 1 — *Governance Hub* — of the [Foundry Citadel Platform](https://github.com/Azure-Samples/foundry-citadel-platform)).

## Canonical artifacts
- **Plan (source of truth):** [.github/prompts/plan-citadelBudgets.prompt.md](.github/prompts/plan-citadelBudgets.prompt.md)
- **Repo conventions:** [.github/copilot-instructions.md](.github/copilot-instructions.md)
- **Specialized agents:** [.github/chatmodes/](.github/chatmodes/)
- **Squad compositions:** [.github/squads.md](.github/squads.md)
- **Task prompts:** [.github/prompts/](.github/prompts/)
- **Scoped instructions:** [.github/instructions/](.github/instructions/)
- **Domain skills:** [.github/skills/](.github/skills/)

## Project anchor (do not drift)
- Upstream: `Azure-Samples/ai-hub-gateway-solution-accelerator`, branch **`citadel-v1`** (~251 commits ahead of `main`, rebranded "Citadel Governance Hub").
- Bootstrap: `azd init --template Azure-Samples/ai-hub-gateway-solution-accelerator -e citadel-budgets-dev --branch citadel-v1`.
- Folder root: **`bicep/infra/`** (not `infra/`).
- Ingestion: **`src/usage-ingestion-logicapp/`** (Logic App, not Function).
- API surface decision (Phase 0): Path A extend Unified AI Wildcard API, vs. Path B dedicated `/anthropic` API. Decided in Phase 0.a spike.

## Locked decisions (D1–D6 — do not re-litigate without an explicit ADR PR)
- **D1 Identity:** Pass-through Entra JWT, audience = Anthropic-published Claude Code app.
- **D2 Granularity:** Hybrid tier + per-user×per-model budgets. Precedence `(oid,model) → (oid,*) → (tier,model) → (tier,*) → global`.
- **D3 Counter store:** Cosmos + APIM `cache-lookup-value` (~30s TTL).
- **D4 Enforcement:** 80% soft warn header, 100% hard 429 with `Retry-After` to next-month UTC. `adminOverride` bypasses.
- **D5 Provisioning:** Bicep-as-code via Citadel Access Contracts (tiers + per-user overlays). Power App deferred.
- **D6 Reporting:** Extend existing PBIX. Fabric deferred.

## Constraint that reshapes everything
Claude Code's JWT is issued to the **Anthropic-published multi-tenant Entra app** — the customer cannot modify its manifest. JWT carries `oid`, `tid`, `preferred_username`, `aud`, `iss` but **no** group/role claims. Tier resolution must be a server-side Entra → Cosmos sync.

## Working agreements
- Plan file is **append-by-amendment** with a visible "Adjustments" section. Never silently rewrite locked sections.
- Every upstream reference uses the `citadel-v1` branch URL.
- Budgets are a **superset overlay** on Citadel Access Contracts — not a replacement. Contract quota = use-case ceiling; per-user budget = fair-share inside it.
- All path references in code/docs use `bicep/infra/` and `src/usage-ingestion-logicapp/`.
- Anthropic usage = `usage.input_tokens` + `usage.output_tokens` (not OpenAI's `total_tokens`). Streaming completion in terminal `message_delta`.
- Backend identity to Foundry: APIM managed identity, **strip user JWT before forwarding**.
