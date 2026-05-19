# Citadel Budgets Error Codes

This document catalogs all error responses from the Citadel Budgets APIM policies and their resolutions.

## Authentication Errors (401)

### CITADEL_AUTH_001
**Message:** `Unauthorized: Citadel JWT validation failed`

**Cause:** JWT validation failed (expired, invalid signature, wrong audience/issuer)

**Resolution:**
1. Verify Claude Code is configured with the correct base URL
2. Check that the JWT audience matches the Claude Code app ID in APIM Named Values
3. Verify the JWT issuer is v2.0 format: `https://login.microsoftonline.com/{tenant-id}/v2.0`
4. Ensure the token is not expired (check `exp` claim)

### CITADEL_AUTH_002
**Message:** `Unauthorized: missing oid claim (app-only tokens are not accepted)`

**Cause:** JWT is missing the `oid` claim (user object ID)

**Resolution:**
1. Ensure the user is signed in with a valid Entra ID user account (not an app-only token)
2. Verify the token was requested with delegated permissions, not application permissions
3. Check that the Claude Code authentication flow is using user delegation

## Budget Enforcement Errors (429)

### CITADEL_BUDGET_001
**Message:** `Budget exceeded: {tier} tier monthly limit reached`

**Response Headers:**
- `x-citadel-budget-pct`: `100` (or close to it)
- `x-citadel-budget-remaining`: `0`
- `Retry-After`: `<seconds-until-next-month-UTC>`

**Cause:** User has consumed 100% of their monthly token budget

**Resolution:**
1. **Wait until next month:** The `Retry-After` header indicates when the budget resets (1st of next month, 00:00 UTC)
2. **Request budget increase:** Contact your AI CoE lead to request a tier upgrade or per-user override
3. **Admin override (emergency only):** If you have `adminOverride=true` claim, requests will bypass budget checks
4. **Check for runaway usage:** Review your recent Claude Code usage in the Power BI dashboard

### CITADEL_BUDGET_002
**Message:** `Budget warning: {tier} tier at {pct}% of monthly limit`

**Response Headers:**
- `x-citadel-budget-pct`: `80-99`
- `x-citadel-budget-remaining`: `<tokens-remaining>`

**Cause:** User is approaching their monthly token budget (soft warning at 80%)

**Resolution:**
1. Monitor your usage in the Power BI dashboard
2. Consider optimizing Claude Code prompts to reduce token consumption
3. Request a tier upgrade proactively if you anticipate exceeding the limit
4. This is a **warning only** - the request will succeed

## Tier Resolution Errors

### CITADEL_TIER_001
**Message:** `Tier not found for user {oid}, defaulting to bronze`

**Cause:** User's tier mapping is missing from the `user-tier` Cosmos container

**Resolution:**
1. **Normal for new users:** The tier-sync Function runs every 6 hours - wait up to 6 hours for tier assignment
2. **Check Entra group membership:** Verify the user is added to a tier group (bronze/silver/gold)
3. **Manual tier-sync trigger:** Azure Portal → tier-sync Function → "Run Now"
4. **Verify tier-sync Function health:** Check Application Insights for tier-sync errors

### CITADEL_TIER_002
**Message:** `Tier-sync stale: last sync > 6 hours ago`

**Cause:** The tier-sync Function hasn't run successfully in >6 hours

**Resolution:**
1. Check tier-sync Function logs in Application Insights
2. Verify the Function's managed identity has `Group.Read.All` permission on Microsoft Graph
3. Check for Graph API throttling or failures
4. Manually trigger the tier-sync Function from Azure Portal

## Data Integrity Errors

### CITADEL_DATA_001
**Message:** `Budget document not found for tier {tier} and model {model}`

**Cause:** Missing budget contract in the `budgets` Cosmos container

**Resolution:**
1. Verify the tier contract Bicep file exists: `bicep/infra/citadel-access-contracts/citadel-tiers/{tier}.bicep`
2. Redeploy the Citadel Access Contracts: `az deployment group create -f main.citadel.bicep`
3. Check Cosmos container `budgets` for the expected document with `scope=tier:{tier}:model:{model}`

### CITADEL_DATA_002
**Message:** `Monthly counter document creation failed`

**Cause:** Logic App failed to create/update the `ai-usage-monthly` Cosmos document

**Resolution:**
1. Check Logic App run history for errors
2. Verify the Logic App's managed identity has Cosmos Data Contributor role
3. Check Cosmos container `ai-usage-monthly` for write throttling (HTTP 429 from Cosmos)
4. Increase Cosmos RU/s if throttling is detected

## Correlation & Debugging

Every error response includes:
- `x-citadel-trace-id`: Correlation ID for tracking across APIM → Event Hub → Logic App → Cosmos
- `x-ms-request-id`: APIM request ID

**To investigate an error:**
1. Copy the `x-citadel-trace-id` value
2. Search Application Insights logs: `customDimensions.citadelTraceId == "<trace-id>"`
3. Review the full request flow across all components

## Runbook: User Reports "429 but I should have budget remaining"

### Investigation Steps

1. **Verify user identity:**
   ```kusto
   // Application Insights query
   traces
   | where customDimensions.userOid == "<user-oid>"
   | where timestamp > ago(1h)
   | project timestamp, message, customDimensions
   ```

2. **Check current budget counter:**
   - Query Cosmos `ai-usage-monthly` container
   - Document ID: `<oid>:<YYYY-MM>:<model>`
   - Compare `tokensUsed` vs tier budget limit

3. **Check tier assignment:**
   - Query Cosmos `user-tier` container
   - Document ID: `<oid>`
   - Verify `tier` field matches expected value
   - Check `updatedAt` is within last 6 hours

4. **Review recent requests:**
   - APIM logs: search for user's `oid` in the last hour
   - Look for budget check failures

5. **Check for cache staleness:**
   - APIM cache TTL is ~30 seconds
   - Counter increments may take up to 30s to reflect
   - If user is exactly at 100%, cache may show stale "under budget" value

### Resolution

- **If counter is accurate:** Explain budget limit, provide `Retry-After` date
- **If counter is incorrect:**
  1. Check Logic App processing for missed events
  2. Verify Event Hub → Logic App → Cosmos pipeline is healthy
  3. Manual correction: update Cosmos document directly (emergency only)
- **If tier is wrong:**
  1. Verify Entra group membership
  2. Trigger tier-sync Function manually
  3. Wait 30s for APIM cache to expire

## Emergency Admin Override

If a user has a legitimate urgent need and cannot wait for budget reset:

1. **Temporary per-user override (recommended):**
   - Create a PR with `bicep/infra/citadel-access-contracts/user-overrides/<oid>.bicep`
   - Set higher monthly limit for this user
   - Deploy the override
   - Document justification + expiry date in the PR

2. **JWT claim override (emergency only):**
   - Add `adminOverride=true` claim to the user's Entra token
   - Requires custom claims policy (not recommended for POC)
   - Bypasses all budget checks

3. **Manual counter reset (last resort):**
   - Query Cosmos `ai-usage-monthly` for user's document
   - Set `tokensUsed = 0`
   - Document the action in the commit message
   - **Only use when counter is provably incorrect**
