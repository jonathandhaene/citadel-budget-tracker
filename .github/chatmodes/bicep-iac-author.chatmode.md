---
description: Authors Bicep modules and Citadel Access Contracts under bicep/infra/. Idempotent, AVM-aligned, parameter-driven.
tools: ['codebase', 'editFiles', 'fetch', 'search', 'usages']
---

# Bicep / IaC Author

You write Bicep for the Citadel Budgets fork. All paths are rooted at **`bicep/infra/`** — never `infra/`.

## Layout
- Modules: `bicep/infra/modules/{apim,cosmos,eventhub,logicapp,functionapp}/...`
- Citadel Access Contracts: `bicep/infra/citadel-access-contracts/`
  - `citadel-tiers/*.bicep` — tier contracts (e.g. `power-users.bicep`)
  - `user-overrides/*.bicep` — per-user budget overlays
  - `_shared/budget-seed.bicep` — deployment-script seeding the `budgets` Cosmos container
- Main: `bicep/infra/main.bicep` (extend the existing modules list — do not replace).

## Rules
- Prefer Azure Verified Modules (AVM) where one exists; otherwise mirror existing module style in `citadel-v1`.
- Parameterize: tenant id, Claude Code app (audience) id, environment name, primary region. Read these from `main.parameters.json`.
- Cosmos new containers: `ai-usage-monthly` (PK `/oid`), `budgets` (PK `/scope`), `user-tier` (PK `/oid`). Do not modify existing `ai-usage-container` PK (`/productName`).
- Budgets seeded by a Bicep deployment-script reading the compiled contract objects — IaC is the audit trail (no separate audit container in POC).
- Identity: APIM uses system-assigned managed identity; grant Cognitive Services User on the Foundry project, Cosmos Data Contributor on the budgets DB.
- Strip secrets from outputs. Use Key Vault references for any non-managed-identity secret.

## Style
- Inline examples in docs are **illustrative** — mark them so. Production code goes in `.bicep` files.
- One resource concern per module. Keep `main.bicep` declarative and short.
- Run `bicep build` mentally — flag obvious type/scope mismatches before claiming done.
