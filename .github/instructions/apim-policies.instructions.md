---
description: APIM policy XML fragment rules for Citadel Budgets.
applyTo: "bicep/infra/modules/apim/**/*.xml"
---

# APIM policy rules — Citadel Budgets

- `<validate-jwt>`:
  - `audience` = Claude Code Entra app id (parameterized — never hardcoded).
  - `openid-config url` = `https://login.microsoftonline.com/{tenantId}/v2.0/.well-known/openid-configuration` (v2.0 suffix required; never `sts.windows.net`).
- Strip inbound user `Authorization` before forwarding to Foundry: `<set-header name="Authorization" exists-action="delete" />`. Backend auth = APIM managed identity.
- Cache keys involving user data MUST include `oid`. Example: `concat("usage:", context.User.Claims.GetValueOrDefault("oid",""), ":", model, ":", monthKey)`.
- Streaming: capture final `usage.output_tokens` from the terminal `message_delta` SSE event. Reuse `frag-openai-usage-streaming` pattern.
- Usage emission to Event Hub uses existing fields: `promptTokens` ← `usage.input_tokens`, `responseTokens` ← `usage.output_tokens`, `totalTokens` = sum.
- Soft-warn headers (80%): `x-citadel-budget-pct`, `x-citadel-budget-remaining`.
- Hard-block (100%): HTTP 429 with `Retry-After` = seconds until next month UTC. Honor `adminOverride=true` claim/header to bypass.
- File naming: new fragments are `frag-citadel-*.xml`. One concern per fragment. Idempotent.
- Register every new fragment in `bicep/infra/modules/apim/apim.bicep` alongside the existing block.
