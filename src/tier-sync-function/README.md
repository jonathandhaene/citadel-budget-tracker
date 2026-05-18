# Citadel tier-sync Function

Resolves Entra tier-group transitive members into the `user-tier` Cosmos container every 6 hours. Required because the Claude Code Entra app does not include `groups` claims in the JWT (D1 constraint).

## Required Entra permissions (admin consent needed)

| API | Permission | Type |
|-----|------------|------|
| Microsoft Graph | `Group.Read.All` | Application |
| Microsoft Graph | `Directory.Read.All` | Application |

Granted to the Function's managed identity via `tier-sync-function.bicep`.

## Required Cosmos role

`Cosmos DB Built-in Data Contributor` on the `ai-usage-db` database (scoped, not account-wide).

## App settings (set by Bicep)

| Setting | Description |
|---------|-------------|
| `COSMOS_ACCOUNT_NAME` | Cosmos account hosting `ai-usage-db` |
| `TIER_GROUP_OID_BRONZE` | Entra group OID for bronze tier (optional — bronze is the fallback for users not in any group) |
| `TIER_GROUP_OID_SILVER` | Entra group OID for silver tier |
| `TIER_GROUP_OID_GOLD`   | Entra group OID for gold tier |

## Schedule

Cron: `0 0 */6 * * *` — every 6 hours at minute 0. Adjust in `tier-sync/function.json` if the customer needs tighter SLAs (faster than 1h is wasteful — group memberships change rarely).

## Local development

```bash
npm install
npm run build
func start
```

You will need a local `local.settings.json` with `AzureWebJobsStorage` and the env vars above.
