---
description: Bicep authoring rules for the Citadel Budgets fork.
applyTo: "bicep/infra/**/*.bicep"
---

# Bicep rules — Citadel Budgets

- Root is `bicep/infra/`. Modules live under `bicep/infra/modules/<area>/`.
- Citadel Access Contracts: tier contracts in `bicep/infra/citadel-access-contracts/citadel-tiers/`, user overlays in `…/user-overrides/`, shared seeder in `…/_shared/budget-seed.bicep`.
- Prefer Azure Verified Modules (AVM); otherwise mirror existing `citadel-v1` module style.
- Parameterize: `tenantId`, `claudeCodeAppId`, `environmentName`, `location`. Pull from `main.parameters.json`.
- Cosmos new containers (do not change existing PKs):
  - `ai-usage-monthly` — PK `/oid`
  - `budgets` — PK `/scope`
  - `user-tier` — PK `/oid`
- APIM uses **system-assigned managed identity**. Grant Cognitive Services User on the Foundry project; Cosmos Data Contributor on the budgets DB. Strip user JWT before forwarding.
- No secrets in module outputs. Use Key Vault refs for any non-MI secret.
- Inline examples in markdown are illustrative — production code goes in `.bicep` files only.
