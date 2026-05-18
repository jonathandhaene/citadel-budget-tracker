---
description: Constraints of the Anthropic-published multi-tenant Entra app used by Claude Code, and Citadel's tier-resolution strategy.
---

# Entra JWT — Claude Code

## The app
Claude Code authenticates against an Entra app **published by Anthropic** in their tenant, used multi-tenant. the customer cannot modify its manifest. Consequence: we cannot add optional claims (no `groups`, no `roles`, no custom claims).

## Available claims
| Claim | Use it for |
|-------|------------|
| `oid` | **Identity / joins.** Stable per user per tenant. Use as Cosmos partition key for usage + tier. |
| `tid` | Tenant id. Always customer's tenant. Validate in JWT policy. |
| `aud` | Audience = Claude Code app id. Validate. |
| `iss` | `https://login.microsoftonline.com/{tid}/v2.0`. Validate (v2.0, never `sts.windows.net`). |
| `preferred_username` | **Display only.** PBIX, logs. |
| `upn` | Null for guests. Don't depend on it. |
| `name` | Display only. |

## Claims that do NOT exist
- ❌ `groups` — would have been useful for tier; not available.
- ❌ `roles` — app-roles can't be set on an app we don't own.
- ❌ Custom claims via extensions — same reason.

## Tier resolution (consequence)
Because tier can't ride on the token, Citadel runs a **server-side tier-sync Function**:
- Reads Entra group membership for each user (Graph API, app permissions).
- Maps groups → tier per a config table.
- Upserts `{ id: <oid>, oid, tier, lastSyncedUtc }` into Cosmos `user-tier`.
- Runs on schedule (e.g., hourly) + on-demand for new users.

APIM's enforcement fragment reads tier from `user-tier` (cached ~30s, D3).

## JWT validation policy snippet (illustrative)
```xml
<validate-jwt header-name="Authorization" failed-validation-httpcode="401" require-scheme="Bearer">
  <openid-config url="https://login.microsoftonline.com/{{tenantId}}/v2.0/.well-known/openid-configuration" />
  <audiences><audience>{{claudeCodeAppId}}</audience></audiences>
  <issuers><issuer>https://login.microsoftonline.com/{{tenantId}}/v2.0</issuer></issuers>
</validate-jwt>
<set-variable name="oid" value="@(context.Principal.Claims.GetValueOrDefault("oid",""))" />
<set-header name="Authorization" exists-action="delete" />
```

## Pitfalls
- Don't validate the v1 issuer `https://sts.windows.net/{tid}/` — Claude Code uses v2.
- Don't try to read `groups` from the token; it's not there.
- `upn` may be empty for guests — never use as a foreign key.
