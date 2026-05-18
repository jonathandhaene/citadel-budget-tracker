# Citadel patch — `ai-usage-ingestion` Logic App workflow

This README describes the Citadel overlay applied to the upstream `ai-usage-ingestion` Logic App workflow. The patch JSON (`workflow.citadel-patch.json`) is NOT a standalone workflow — it is a set of three actions to be inserted into the existing upstream `workflow.json`.

## What it does

For every usage event received from APIM (via Event Hub), the patch maintains a per-user × per-model **monthly aggregate counter** in the new Cosmos container `ai-usage-monthly`. This counter is the authoritative `usedTokens` value read by the APIM `citadel-budget-check` fragment at request time.

## Document model

```jsonc
// Container: ai-usage-monthly  | Partition key: /oid  | TTL: 90 days
{
  "id":          "<oid>:<YYYY-MM>:<model>",  // e.g. "a1b2c3d4-...:2026-05:claude-sonnet-4"
  "oid":         "a1b2c3d4-...",
  "upn":         "alice@contoso.com",
  "month":       "2026-05",
  "model":       "claude-sonnet-4",
  "totalTokens": 142387,
  "updatedAt":   "2026-05-13T08:14:01Z"
}
```

## Inserted actions

| # | Name | Type | Purpose |
|---|------|------|---------|
| 1 | `Project_userOid_userUpn_month` | Compose | Derive `docId`, `oid`, `upn`, `month`, `model`, `totalTokens` from the incoming usage event |
| 2 | `Upsert_ai_usage_monthly` | Cosmos PATCH | Increment `/totalTokens` via JSON-patch `add` op; sets other fields via `set` ops |
| 3 | `Create_ai_usage_monthly_if_missing` | Cosmos POST (upsert) | Fallback runs only if (2) failed (doc didn't exist yet — first event of the month for this user×model) |

## Insertion point

Insert after the existing `Parse_Usage_Event` action and **before** the existing `Send_to_ai-usage` action — both the upstream container write and the Citadel monthly counter run in parallel (both `runAfter: Parse_Usage_Event`).

## Verification

After deploy, send a test message through the Anthropic API and verify:

```bash
az cosmosdb sql container query \
  --account-name "$COSMOS_ACCOUNT" \
  --database-name ai-usage-db \
  --container-name ai-usage-monthly \
  --query-text "SELECT * FROM c WHERE c.oid = '<your-oid>' AND c.month = '$(date -u +%Y-%m)'"
```

Expect `totalTokens` to grow monotonically with each new request.

## Race condition note

`/totalTokens` increments use the Cosmos JSON-patch `add` op which is server-side atomic — no read-modify-write. Multiple concurrent requests from the same user are safe.

## Out of scope

- Per-day or per-hour granularity (PBIX dashboards already aggregate from the upstream `ai-usage` container which retains raw events).
- Cross-model budget aggregation (handled by the `*` scope in the budget precedence — not by aggregating documents).
