---
description: Citadel Access Contracts — schema, deploy flow, and how budgets layer on top.
---

# Citadel Access Contracts

Citadel's existing "Access Contracts" govern *what a tier or user is allowed to call*. Citadel adds *how much they can spend* on top — budgets are a **superset overlay**, not a replacement.

## Folder layout
```
bicep/infra/citadel-access-contracts/
├── citadel-tiers/          # one .bicep per tier (tier-1, tier-2, …)
├── user-overrides/         # per-user overlays, sparse
└── _shared/
    └── budget-seed.bicep   # deployment-script that writes to Cosmos `budgets`
```

## Tier contract (illustrative — not production)
```bicep
// citadel-tiers/tier-2.bicep
param tierName string = 'tier-2'

var allowedModels = [
  'claude-3-5-sonnet-*'
  'claude-3-7-sonnet-*'
  'gpt-4o-*'
]

var budgets = {
  '*':                     500000     // wildcard tokens/month
  'claude-3-7-sonnet-*':   200000     // model-specific cap
}
```

## Per-user overlay (sparse — only diffs from tier)
```bicep
// user-overrides/<oid>.bicep
param oid string
var budgets = {
  'claude-3-7-sonnet-*': 1000000      // raise this user's cap above their tier
}
```

## Seed pipeline
1. `main.bicep` iterates tier + override files.
2. `_shared/budget-seed.bicep` runs a deployment script that upserts into Cosmos `budgets`:
   - Tier rows: `{ scope: "tier:2", model: "*", limitTokens: 500000 }`
   - User rows: `{ scope: "user:<oid>", model: "claude-3-7-sonnet-*", limitTokens: 1000000 }`
3. Idempotent — re-running the deployment is the audit trail (D5; no separate audit container in the POC).

## Quota vs budget — distinction
| | Quota (existing Access Contracts) | Budget (Citadel addition) |
|---|---|---|
| Unit | request count / RPS | tokens / month |
| Scope | tier or product | tier OR user × model |
| Enforcement | APIM rate-limit policies | APIM custom fragment + Cosmos lookup |
| Override | n/a | `adminOverride=true` |

## Precedence (locked — D2)
`(user, model) → (user, *) → (tier, model) → (tier, *) → global`

## Out of scope (POC)
- Power App admin UI for editing contracts (D5).
- Cost-based (USD) budgets — tokens only for now.
