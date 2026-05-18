---
description: Validation notebook conventions.
applyTo: "validation/**/*.ipynb"
---

# Validation notebook rules

- One scenario per cell. Use markdown headers citing the phase number (e.g., `## Phase 4c — 100% block returns 429`).
- Parameterize at the top of the notebook (APIM endpoint, tenant id, Claude Code app id, test users). Read from env vars; never commit tokens.
- Use `assert` statements (not just `print`) so re-runs surface regressions.
- Test matrix to cover when relevant:
  - JWT acceptance (v2.0 issuer).
  - Inbound `Authorization` is stripped (verify via Foundry-side log or by sending a poison token).
  - Non-streaming usage capture (`usage.input_tokens` + `usage.output_tokens`).
  - Streaming usage capture from terminal `message_delta`.
  - Budget warn header at 80%.
  - Budget block 429 + `Retry-After` at 100%.
  - `adminOverride` bypass.
  - Tier resolution: `(oid,model) → (oid,*) → (tier,model) → (tier,*) → global`.
- Do not commit cell outputs that include real tokens or oids — clear before committing.
