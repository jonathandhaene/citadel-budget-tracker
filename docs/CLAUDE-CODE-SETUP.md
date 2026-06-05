# Claude Code Setup Guide for Citadel Budgets

> **Enabling Claude Code with Azure API Management and Microsoft Foundry**
>
> This guide shows developers how to configure Claude Code (Anthropic's AI coding assistant) to work through the Citadel Budgets governance layer, connecting to Claude models hosted in Microsoft Foundry with per-user budget enforcement.

## Overview

Claude Code can connect to Anthropic's Claude models running in Microsoft Foundry through our Citadel-governed API Management layer. This setup provides:

- **Centralized authentication** via Microsoft Entra ID (no individual Anthropic API keys)
- **Budget enforcement** per user, per model, with soft warnings at 80% and hard blocks at 100%
- **Usage tracking** with Power BI dashboards showing consumption by user, model, and tier
- **Cost control** preventing runaway usage and billing surprises

## Architecture

```
┌──────────────┐         ┌─────────────────────────────────────┐         ┌─────────────┐
│              │  HTTPS  │  Azure API Management               │  HTTPS  │             │
│  Claude Code │────────▶│  /anthropic/v1/messages             │────────▶│  Microsoft  │
│  (Local CLI  │  +JWT   │  · Entra JWT validation             │  +MI    │  Foundry    │
│   or VS Code)│         │  · Budget check (oid-based cache)   │         │  (Anthropic │
│              │         │  · Usage telemetry → Event Hub      │         │   Models)   │
└──────────────┘         └─────────────────────────────────────┘         └─────────────┘
                                          │
                                          ▼
                                  ┌──────────────┐
                                  │ Cosmos DB    │
                                  │ · user-tier  │
                                  │ · budgets    │
                                  │ · ai-usage-* │
                                  └──────────────┘
```

## Prerequisites

1. **Microsoft Foundry Access**
   - Active Azure subscription with Foundry enabled
   - Claude models deployed in Foundry (recommended deployment names below)
   - Managed Identity or API key for Foundry authentication

2. **Citadel Budgets Deployment**
   - APIM instance with Citadel Anthropic API configured
   - User assigned to a tier (bronze/silver/gold) via Entra group membership
   - Budget limits configured for your tier

3. **Claude Code Installation**
   - Claude Code CLI or VS Code extension installed
   - Microsoft Entra credentials (Azure CLI or interactive login)

## Step 1: Deploy Claude Models in Microsoft Foundry

### Recommended Deployment Names

To ensure compatibility with Claude Code defaults, use these exact deployment names in Foundry:

| Model Tier | Deployment Name | Foundry Model ID |
|------------|----------------|------------------|
| Fast, lightweight | `claude-haiku-4-5` | `claude-haiku-4-5-20250514` |
| Balanced, default | `claude-sonnet-4-5` | `claude-sonnet-4-5-20250929` |
| Most capable | `claude-opus-4-5` | `claude-opus-4-5-20251101` |

> **Note**: Claude Code looks for these deployment names by default. Using different names requires explicit environment variable overrides (see Step 3).

### Deployment Steps

1. Navigate to [ai.azure.com](https://ai.azure.com)
2. Select your Foundry resource (or create one)
3. Go to **Models + endpoints** → **Deploy model**
4. Select each Claude model version and deploy with the names above
5. Note the Foundry resource endpoint (e.g., `https://<resource>.api.foundry.ml.azure.com`)

## Step 2: Configure Authentication

Citadel Budgets supports **Entra ID authentication only** for Claude Code (no API keys are distributed to end users). Your JWT token is validated by APIM and mapped to your budget tier.

### Verify Your Entra Identity

```bash
# Login with Azure CLI (if not already authenticated)
az login

# Confirm your identity
az account show --query "{Name:name, UserPrincipalName:user.name, TenantId:tenantId}"
```

The `UserPrincipalName` corresponds to the `preferred_username` claim in your JWT, which is used for display in Power BI dashboards. The `oid` (object ID) claim is used as your stable identity key for budget enforcement.

### Verify Your Tier Assignment

Your budget tier is determined by Entra group membership:

```bash
# List your group memberships (requires Microsoft Graph permissions)
az ad signed-in-user list-group-memberships --query "[].{DisplayName:displayName, ObjectId:id}" -o table
```

Look for group names matching your organization's tier convention (e.g., "claude-users-gold"). If you're not in any tier group, you'll be assigned the **standard** tier (default).

## Step 3: Configure Claude Code Environment Variables

### Required Variables

```bash
# Point Claude Code to the Citadel APIM gateway (NOT directly to Foundry)
export ANTHROPIC_BASE_URL="https://<your-apim-gateway>.azure-api.net/anthropic/v1"

# Optional: If using API key fallback (typically not recommended for Citadel)
# export ANTHROPIC_API_KEY="<foundry-api-key>"
#
# Citadel deployments should rely on Entra ID authentication instead.
# When ANTHROPIC_API_KEY is unset, Claude Code uses Azure credential chain.
```

### Optional: Override Default Model Deployment Names

If your Foundry deployments use different names:

```bash
export ANTHROPIC_DEFAULT_SONNET_MODEL="<your-sonnet-deployment-name>"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="<your-haiku-deployment-name>"
export ANTHROPIC_DEFAULT_OPUS_MODEL="<your-opus-deployment-name>"
```

### Complete Setup Example

Add to your `~/.bashrc`, `~/.zshrc`, or equivalent:

```bash
# Citadel Budgets - Claude Code Configuration
export ANTHROPIC_BASE_URL="https://citadel-apim-prod.azure-api.net/anthropic/v1"

# Azure authentication (Claude Code will use az CLI creds or interactive login)
# No ANTHROPIC_API_KEY needed - Entra JWT is sent in Authorization header

# Optional: VS Code extension support
export CLAUDE_CODE_BASE_URL="$ANTHROPIC_BASE_URL"
```

Reload your shell:

```bash
source ~/.bashrc  # or ~/.zshrc
```

## Step 4: Test Your Connection

### CLI Test

```bash
# Start an interactive Claude Code session
claude

# Or run a one-shot command
echo "Write a hello world in Python" | claude
```

**Expected behavior:**
- Claude Code sends request to APIM with your Entra JWT in `Authorization: Bearer <token>`
- APIM validates JWT, extracts your `oid`, checks your budget
- If under budget, request is forwarded to Foundry (with APIM Managed Identity auth)
- Response headers include `x-citadel-budget-pct` and `x-citadel-budget-remaining`

### Check Response Headers

Enable verbose mode to see budget headers:

```bash
# Most HTTP clients show headers with -v
curl -v -H "Authorization: Bearer $(az account get-access-token --resource <claude-code-app-id> --query accessToken -o tsv)" \
     -H "Content-Type: application/json" \
     -d '{"model":"claude-sonnet-4-5","messages":[{"role":"user","content":"Hello"}],"max_tokens":100}' \
     "$ANTHROPIC_BASE_URL/messages"
```

Look for:
```
x-citadel-budget-pct: 42
x-citadel-budget-remaining: 2900000
```

## Step 5: Understand Budget Enforcement

### Soft Warning (80% threshold)

When you reach 80% of your monthly budget:

```http
HTTP/1.1 200 OK
x-citadel-budget-pct: 85
x-citadel-budget-remaining: 750000
x-citadel-budget-warning: Approaching monthly limit. 15% remaining.
```

Claude Code continues to work. Consider reducing usage or requesting a tier upgrade.

### Hard Block (100% threshold)

When you exceed 100% of your monthly budget:

```http
HTTP/1.1 429 Too Many Requests
Retry-After: 432000
Content-Type: application/json

{
  "error": {
    "type": "rate_limit_error",
    "message": "Monthly budget exhausted. Resets at start of next calendar month (UTC)."
  }
}
```

**Retry-After** header shows seconds until next month (UTC midnight on the 1st).

### Admin Override

In exceptional cases, your admin can set `adminOverride: true` on your budget document, which bypasses the 100% block. This is logged for audit purposes.

## Step 6: Monitor Your Usage

### Power BI Dashboard

Your organization's Citadel Power BI dashboard shows:

- **Your Usage by Model**: Tokens consumed this month, per model
- **Budget Percentage**: Current percentage for your tier and user-specific overrides
- **Top Consumers**: Relative ranking (anonymized `oid` unless you're an admin)

Ask your admin for the dashboard URL.

### Azure Portal (Admin View)

Admins can query Cosmos DB directly:

```sql
-- Cosmos DB SQL query: check user's current month usage
SELECT c.userOid, c.model, c.totalTokens, c.month
FROM c
WHERE c.userOid = '<your-oid>'
  AND c.month = '2026-06'
```

## Troubleshooting

### Issue: 401 Unauthorized

**Cause**: JWT validation failed.

**Check**:
1. Is `az account show` returning the correct tenant?
2. Is your token audience correct? (Should be the Claude Code app ID configured in APIM)
3. Is the issuer v2.0? (Citadel requires `https://login.microsoftonline.com/{tid}/v2.0`)

**Fix**: Ensure you're logged into the correct tenant:
```bash
az logout
az login --tenant <correct-tenant-id>
```

### Issue: 429 Too Many Requests (Immediate)

**Cause**: You've hit your monthly budget limit.

**Check**: Current date/time. Budgets reset at UTC midnight on the 1st of each month.

**Fix**:
- Wait until next month, or
- Request a tier upgrade (Entra group membership change), or
- Request a per-user budget override (requires admin approval + Bicep PR)

### Issue: Claude Code not finding models

**Cause**: Deployment names in Foundry don't match Claude Code's expected defaults.

**Fix**: Set explicit deployment name overrides (Step 3).

### Issue: Slow responses

**Cause**: Budget check cache miss (30s TTL). First request after cache expiry reads from Cosmos.

**Expected**: ~100-200ms latency on cache miss, <10ms on cache hit. Subsequent requests within 30s are fast.

## Environment Variable Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ANTHROPIC_BASE_URL` | **Yes** | `https://api.anthropic.com` | Set to your Citadel APIM gateway URL + `/anthropic/v1` |
| `ANTHROPIC_API_KEY` | No | (unset) | **Do not set** for Citadel. Entra JWT auth is used instead. |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | No | `claude-sonnet-4-5` | Override if Foundry deployment name differs |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | No | `claude-haiku-4-5` | Override if Foundry deployment name differs |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | No | `claude-opus-4-5` | Override if Foundry deployment name differs |
| `CLAUDE_CODE_BASE_URL` | No | (mirrors `ANTHROPIC_BASE_URL`) | For VS Code extension compatibility |

## Security Notes

### What Citadel Does

- **Validates your Entra JWT** (audience + issuer + signature)
- **Extracts your `oid`** (user object ID) for budget lookups
- **Strips your JWT before forwarding to Foundry** (Foundry never sees your user identity)
- **Attaches APIM Managed Identity bearer** for backend auth to Foundry

### What You Should Never Do

- ❌ Share your `ANTHROPIC_BASE_URL` publicly (it's org-internal)
- ❌ Set `ANTHROPIC_API_KEY` in Citadel deployments (defeats per-user budgeting)
- ❌ Bypass APIM by calling Foundry directly (no budget enforcement)

## Next Steps

- Review your tier's monthly limits: see [citadel-access-contracts/citadel-tiers/](../bicep/infra/citadel-access-contracts/citadel-tiers/)
- Request a tier change: contact your admin with business justification
- Report usage anomalies: check Power BI dashboard first, then file a ticket

## References

- **Blog post**: [Giving developers Claude Code with Azure API Management and Claude models in Microsoft Foundry](https://techcommunity.microsoft.com/blog/azure-ai-foundry-blog/giving-developers-claude-code-with-azure-api-management-and-claude-models-in-mic/4525212)
- **Citadel plan**: [.github/prompts/plan-citadelBudgets.prompt.md](../.github/prompts/plan-citadelBudgets.prompt.md)
- **Validation notebooks**: [validation/](../validation/)
- **Microsoft Learn**: [Deploy and use Claude models in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/ai-services/foundry/deploy-anthropic-claude)
