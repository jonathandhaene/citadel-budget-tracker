---
description: APIM budget-check + enforcement pattern for Citadel (referenced by apim-policy-author chat mode).
applyTo: "bicep/infra/modules/apim/**/*.xml"
---

# APIM Budget Enforcement

The enforcement fragment (proposed name: `frag-citadel-budget.xml`) runs in `inbound` before forwarding to Foundry.

## Pipeline
```
inbound:
  1. validate-jwt              (frag-aad-auth)
  2. extract oid + tid claims  → context.Variables["oid"], ["tid"]
  3. resolve tier              (cache-lookup → Cosmos read user-tier on miss, ~30s TTL)
  4. resolve budget            (precedence chain — see below)
  5. resolve month-to-date     (cache-lookup → Cosmos read ai-usage-monthly id=<oid>:<yyyy-MM>:<model>)
  6. compute pct = used / limit
  7. if pct >= 1.0 AND NOT adminOverride: return 429 + Retry-After
  8. else set headers x-citadel-budget-pct, x-citadel-budget-remaining
  9. strip Authorization
backend: (forward to Foundry, MI auth)
outbound:
  10. emit usage to Event Hub (frag-ai-usage or frag-openai-usage-streaming for SSE)
```

## Budget precedence (locked — D2)
Resolve in order; first match wins:
1. `(oid, model)` — `user:<oid>` scope, model-specific
2. `(oid, *)` — `user:<oid>` scope, wildcard model
3. `(tier, model)` — `tier:<n>` scope, model-specific
4. `(tier, *)` — `tier:<n>` scope, wildcard model
5. `global` — `scope: "global"`

Maximum 5 Cosmos point-reads, but cache the resolved result keyed by `(oid, model)` with ~30s TTL.

## Cache keys (must include `oid` to prevent cross-user bleed)
```xml
<cache-lookup-value
  key="@("tier:" + context.Variables.GetValueOrDefault<string>("oid",""))"
  variable-name="tier" />

<cache-lookup-value
  key='@("budget:" + context.Variables.GetValueOrDefault<string>("oid","") + ":" + (string)context.Variables["model"])'
  variable-name="budget" />

<cache-lookup-value
  key='@("usage:" + context.Variables.GetValueOrDefault<string>("oid","") + ":" + DateTime.UtcNow.ToString("yyyy-MM") + ":" + (string)context.Variables["model"])'
  variable-name="usedTokens" />
```

## Headers
| Header | When | Value |
|--------|------|-------|
| `x-citadel-budget-pct` | every request | `0.0`–`1.0`, 3 decimals |
| `x-citadel-budget-remaining` | every request | tokens remaining (clamped ≥ 0) |
| `Retry-After` | 429 only | seconds until 1st of next month UTC |

## `adminOverride`
Bypass only if the request carries `adminOverride=true` AND the JWT subject is in the admin allow-list (resolved via tier=`admin` in `user-tier`, OR a future explicit allow-list — TBD). Emit usage anyway so admins show up in PBIX.

## What NOT to do
- ❌ Cache without `oid` in the key.
- ❌ Read Cosmos on every request without cache-lookup.
- ❌ Forward the user's inbound `Authorization` header.
- ❌ Use `sts.windows.net` issuer (v1 token). Must be `https://login.microsoftonline.com/{tid}/v2.0`.
- ❌ Capture `output_tokens` from intermediate SSE deltas — only from terminal `message_delta`.
