# Power BI report — Citadel patch

> Delta against [`_upstream/src/usage-reports/AI-Hub-Gateway-Usage-Report-v1-5-Incremetal.pbix`](../../_upstream/src/usage-reports/AI-Hub-Gateway-Usage-Report-v1-5-Incremetal.pbix). The PBIX is binary — this file documents the in-Desktop edits a customer BI engineer applies once after first import.

## What changes vs. upstream

| Area | Upstream | Citadel addition |
|------|----------|-------------------|
| Dimension grain | `appId` / `subscriptionId` / `productName` | **+ `endUserId` (= Entra `oid`)**, **+ `tier`** (joined from `user-tier` Cosmos container), **+ `preferred_username`** for display |
| Models in `model-pricing` | OpenAI family | **+ 3 Anthropic Claude rows** (see [model-pricing.citadel.json](model-pricing.citadel.json)) |
| Token fields | `promptTokens`, `responseTokens`, `totalTokens` | **Unchanged.** APIM maps Anthropic `usage.input_tokens` → `promptTokens` and `usage.output_tokens` → `responseTokens`, so schema-compatible. |
| Source containers | `ai-usage` (Event Hub sink) + `model-pricing` | **+ `user-tier`** (PK `/oid`) for tier dim, **+ `ai-usage-monthly`** (PK `/oid`) for live budget gauges |
| Visuals | Cost by product/model/region | **+ "Top users by month"** table, **+ "Tier budget utilization"** stacked bar, **+ "Users ≥80% / ≥100%"** card |

## Step 1 — Load `model-pricing.citadel.json` into Cosmos

```bash
az cosmosdb sql container query \
  --account-name <cosmos-account> \
  --database-name ai-usage-db \
  --name model-pricing \
  --query-text "SELECT VALUE COUNT(1) FROM c WHERE STARTSWITH(c.id, 'citadel-')"
# expect: 0 (pre-seed) → 3 (post-seed)
```

Upsert each entry from [model-pricing.citadel.json](model-pricing.citadel.json) (Cosmos Data Explorer or `az cosmosdb sql` upsert script). Prices are list (May 2026); update before Phase 4 sign-off.

## Step 2 — Add `user-tier` data source in Power BI Desktop

1. **Home → Transform data → Data source settings → Change Source** on the existing Cosmos connection. Keep account/db; add second table `user-tier`.
2. In Power Query, expand `Document` column → keep `oid`, `tier`, `preferred_username`, `lastSyncedUtc`. Rename query to `UserTier`.
3. **Model view → New relationship**: `ai-usage[endUserId]` (Many) → `UserTier[oid]` (One). Cross-filter: Single → UserTier filters Usage.

## Step 3 — Add `ai-usage-monthly` data source (live budget)

Same pattern, table `ai-usage-monthly`. Columns to keep: `oid`, `model`, `month`, `totalTokens`. Build a relationship to `UserTier[oid]`. Set refresh to **DirectQuery** (or a 15-minute schedule) so the budget gauges aren't stale.

## Step 4 — DAX measures (paste into the existing `Measures` table)

```DAX
-- Tier monthly limit lookup (replace constants with your tier values from main.citadel.bicepparam)
Tier Monthly Limit =
SWITCH(
    SELECTEDVALUE(UserTier[tier]),
    "bronze",   200000,
    "silver",  1000000,
    "gold",    5000000,
    BLANK()
)

-- % of monthly budget consumed (current calendar month)
Budget % =
VAR cur = SUM('ai-usage-monthly'[totalTokens])
VAR lim = [Tier Monthly Limit]
RETURN DIVIDE(cur, lim)

-- Users at warn (>=80%) and block (>=100%)
Users at Warn =
CALCULATE(
    DISTINCTCOUNT(UserTier[oid]),
    FILTER(VALUES(UserTier[oid]), [Budget %] >= 0.80 && [Budget %] < 1)
)

Users Blocked =
CALCULATE(
    DISTINCTCOUNT(UserTier[oid]),
    FILTER(VALUES(UserTier[oid]), [Budget %] >= 1)
)
```

## Step 5 — Visuals to add

| Page | Visual | Fields |
|------|--------|--------|
| **Existing "Usage" page** | Add slicer | `UserTier[tier]` |
| **New page "Per-user"** | Table | `UserTier[preferred_username]`, `UserTier[tier]`, `[Budget %]`, `SUM(totalTokens)` — sort by `[Budget %]` desc |
| **New page "Per-user"** | Card × 2 | `[Users at Warn]`, `[Users Blocked]` |
| **New page "Per-user"** | Stacked column | Axis: `UserTier[tier]`, Value: `SUM(ai-usage-monthly[totalTokens])`, Tooltip: `[Tier Monthly Limit]` |

## Step 6 — Privacy / disclosure

The report now joins on `oid` and shows `preferred_username`. Confirm with customer DPO that this is in-scope of the existing AI usage notice **before** publishing the workspace. PBIX RLS is recommended on the `tier` dim for non-admin viewers.

## Out of scope (Phase 6+)

- Fabric migration (currently PBIX import + scheduled refresh; Fabric DirectLake deferred).
- Cost-based budgets (current budgets are token-based; cost is a derived measure here, not enforced).
- Cross-month historic budget compliance dashboard (Cosmos `ai-usage-monthly` has 90-day TTL; archive to Fabric Lakehouse if you need year-over-year).
