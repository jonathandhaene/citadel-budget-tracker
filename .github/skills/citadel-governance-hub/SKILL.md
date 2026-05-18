---
description: Layout, conventions, and key files of the Citadel Governance Hub (citadel-v1 branch of ai-hub-gateway-solution-accelerator).
---

# Citadel Governance Hub

Upstream: [`Azure-Samples/ai-hub-gateway-solution-accelerator@citadel-v1`](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/tree/citadel-v1). Branch is ~251 commits ahead of `main` and rebranded "Citadel Governance Hub". Always reference `citadel-v1`, never `main`.

## Bootstrap
```
azd init --template Azure-Samples/ai-hub-gateway-solution-accelerator \
         -e citadel-budgets-dev \
         --branch citadel-v1
```

## Key paths
| Path | What it is |
|------|-----------|
| `bicep/infra/` | IaC root (NOT `infra/`) |
| `bicep/infra/main.bicep` | Top-level orchestrator |
| `bicep/infra/modules/apim/apim.bicep` | APIM service + fragment registration block |
| `bicep/infra/modules/apim/apis/` | API definitions (Unified AI Wildcard lives here) |
| `bicep/infra/modules/apim/policies/` | Reusable XML fragments |
| `bicep/infra/citadel-access-contracts/citadel-tiers/` | Tier contracts |
| `bicep/infra/citadel-access-contracts/user-overrides/` | Per-user contract overlays |
| `bicep/infra/citadel-access-contracts/_shared/budget-seed.bicep` | Deployment-script seeder |
| `src/usage-ingestion-logicapp/` | Logic App workflow JSON (ingestion target) |
| `validation/citadel-jwt-authentication-tests.ipynb` | JWT acceptance harness |

## Reusable APIM fragments (already in upstream)
- `frag-aad-auth.xml` — Entra JWT validation pattern.
- `frag-ai-usage.xml` — non-streaming usage emission to Event Hub.
- `frag-openai-usage-streaming.xml` — SSE streaming usage capture.

## Existing Cosmos containers (do not change PKs)
- `ai-usage-container` — PK `/productName`
- `model-pricing`
- `pii-usage-container`
- `streaming-export-config`

## What Citadel adds (this fork)
- Anthropic surface (`POST /v1/messages` + SSE).
- Pass-through Entra JWT (D1).
- Hybrid tier + per-user × per-model budgets (D2).
- Cosmos containers: `ai-usage-monthly`, `budgets`, `user-tier`.
- Soft + hard budget enforcement with `adminOverride` bypass.
- PBIX schema extension (no Fabric in POC).
