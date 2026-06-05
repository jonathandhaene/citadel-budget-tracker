# Microsoft Foundry Deployment Configuration for Citadel Budgets

> **Deployment naming conventions, endpoint structure, and authentication patterns for Claude models in Microsoft Foundry**

This document captures the Microsoft Foundry-specific configuration details discovered from the [Azure TechCommunity blog post](https://techcommunity.microsoft.com/blog/azure-ai-foundry-blog/giving-developers-claude-code-with-azure-api-management-and-claude-models-in-mic/4525212) and related Microsoft Learn documentation, ensuring Citadel Budgets aligns with Microsoft's recommended practices.

---

## 1. Foundry Endpoint Structure

Microsoft Foundry provides a **unified multi-model API surface** with provider-specific routing:

```
https://<foundry-resource-name>.api.foundry.ml.azure.com/
│
├── /openai/v1/           ← OpenAI-compatible models (GPT-4, GPT-3.5, etc.)
│   └── /chat/completions
│   └── /completions
│   └── /embeddings
│
└── /anthropic/v1/        ← Anthropic Claude models
    └── /messages         ← POST for chat completions (Citadel target)
    └── /complete         ← Legacy completion endpoint (not used by Claude Code)
```

### Citadel Budgets Mapping

Our APIM `/anthropic` API must:
- **Accept**: `https://<apim-gateway>.azure-api.net/anthropic/v1/messages`
- **Forward to**: `https://<foundry-resource>.api.foundry.ml.azure.com/anthropic/v1/messages`

The path suffix `/anthropic/v1` is a **Foundry standard** and should not be customized.

---

## 2. Claude Model Deployment Names

### Recommended Names (Claude Code Defaults)

Claude Code CLI and VS Code extension expect these deployment names by default:

| Model Family | Default Deployment Name | Foundry Model ID (as of June 2026) |
|--------------|------------------------|-------------------------------------|
| **Haiku** (fast, cost-effective) | `claude-haiku-4-5` | `claude-haiku-4-5-20250514` |
| **Sonnet** (balanced, recommended) | `claude-sonnet-4-5` | `claude-sonnet-4-5-20250929` |
| **Opus** (most capable) | `claude-opus-4-5` | `claude-opus-4-5-20251101` |

> **Why these names?**
> Anthropic's official tooling (including Claude Code) uses these as hardcoded defaults. Using different deployment names requires every developer to set environment variable overrides, increasing support burden.

### Deployment Name in Requests

Claude Code sends the deployment name in the `model` field of the request body:

```json
POST /anthropic/v1/messages
{
  "model": "claude-sonnet-4-5",
  "messages": [...],
  "max_tokens": 1024
}
```

Foundry routes the request to the deployment with that exact name. If no such deployment exists, Foundry returns **404 Model Not Found**.

### Custom Deployment Names (Not Recommended)

If organizational policy requires different names (e.g., `claude-prod-sonnet-2026`):

1. Deploy models with custom names in Foundry
2. Document the mapping in your org wiki
3. Require all developers to set environment overrides:

```bash
export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-prod-sonnet-2026"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-prod-haiku-2026"
export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-prod-opus-2026"
```

**Trade-off**: Increased onboarding friction vs. naming convention compliance.

---

## 3. Authentication Patterns

### Foundry-Side Authentication (APIM → Foundry)

Foundry supports two authentication modes:

#### Option A: API Key (Simpler, Less Secure)

```http
POST https://<foundry>.api.foundry.ml.azure.com/anthropic/v1/messages
x-api-key: <foundry-project-api-key>
Content-Type: application/json
```

**Citadel approach**: Store API key in APIM Named Value `foundry-api-key`, inject via policy:

```xml
<set-header name="x-api-key" exists-action="override">
    <value>{{foundry-api-key}}</value>
</set-header>
```

**Limitation**: Project-level key cannot distinguish which APIM user made the call. Foundry logs show all traffic as the APIM identity.

#### Option B: Managed Identity (Recommended)

```xml
<authentication-managed-identity resource="https://cognitiveservices.azure.com" />
```

APIM requests an Azure AD access token for the **Cognitive Services resource scope** and attaches it as `Authorization: Bearer <token>`.

**Citadel current implementation**: Uses Option B (see [`anthropic-api-policy.xml:43`](../bicep/infra/modules/apim/policies/anthropic-api-policy.xml#L43)).

**Benefit**: Foundry can log the APIM service principal identity, enabling per-service audit trails (though still not per-user, as the user JWT is stripped per D1).

### Client-Side Authentication (Claude Code → APIM)

Claude Code supports **dual authentication modes**, controlled by environment variables:

#### Mode 1: API Key (Not Used in Citadel)

```bash
export ANTHROPIC_API_KEY="<key>"
```

Claude Code sends `x-api-key: <key>` header. APIM would validate this, but **Citadel does not use this mode** because:
- No per-user identity (all users share one key)
- No budget enforcement per user
- Key rotation is operationally expensive

#### Mode 2: Azure Credential Chain (Citadel Standard)

```bash
# ANTHROPIC_API_KEY is unset
export ANTHROPIC_BASE_URL="https://<apim>.azure-api.net/anthropic/v1"
```

Claude Code automatically uses the **Azure credential chain**:
1. Environment credentials (`AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, etc.)
2. Azure CLI credentials (`az login`)
3. Managed Identity (if running in Azure)
4. Interactive browser login

Claude Code requests a token with **audience = Anthropic's multi-tenant app ID** and **issuer = customer's Entra tenant**, then sends:

```http
Authorization: Bearer <entra-jwt>
```

APIM validates this JWT per [`frag-citadel-anthropic-auth.xml`](../bicep/infra/modules/apim/policies/frag-citadel-anthropic-auth.xml).

---

## 4. Foundry Resource and Deployment Setup (Admin Guide)

### Step 1: Create Foundry Resource

```bash
# Via Azure CLI
az ml workspace create \
  --name citadel-foundry-prod \
  --resource-group citadel-budgets-rg \
  --location eastus2

# Note the workspace endpoint
FOUNDRY_ENDPOINT=$(az ml workspace show \
  --name citadel-foundry-prod \
  --resource-group citadel-budgets-rg \
  --query discoveryUrl -o tsv | sed 's|/discovery||')

echo "Foundry endpoint: $FOUNDRY_ENDPOINT"
# Example output: https://citadel-foundry-prod.eastus2.api.foundry.ml.azure.com
```

### Step 2: Deploy Claude Models

Via [ai.azure.com](https://ai.azure.com):

1. Navigate to your Foundry resource
2. Select **Models + endpoints** → **Deploy model**
3. Search for "Claude"
4. Deploy each model:

| Model Display Name | Deployment Name (CRITICAL) | Version / Model ID |
|--------------------|----------------------------|---------------------|
| Claude 3.5 Haiku | **`claude-haiku-4-5`** | `claude-haiku-4-5-20250514` |
| Claude 3.5 Sonnet | **`claude-sonnet-4-5`** | `claude-sonnet-4-5-20250929` |
| Claude 3.5 Opus | **`claude-opus-4-5`** | `claude-opus-4-5-20251101` |

5. Configure deployment settings:
   - **Capacity**: Start with 100 TPM (tokens per minute), scale as needed
   - **Region**: Match APIM region for latency
   - **Endpoint**: Note the full URL (should be `<foundry>/anthropic/v1/...`)

### Step 3: Grant APIM Managed Identity Access

```bash
# Get APIM Managed Identity principal ID
APIM_PRINCIPAL_ID=$(az apim show \
  --name citadel-apim-prod \
  --resource-group citadel-budgets-rg \
  --query identity.principalId -o tsv)

# Assign "Cognitive Services OpenAI User" role to APIM MI
az role assignment create \
  --assignee $APIM_PRINCIPAL_ID \
  --role "Cognitive Services OpenAI User" \
  --scope /subscriptions/<sub-id>/resourceGroups/citadel-budgets-rg/providers/Microsoft.MachineLearningServices/workspaces/citadel-foundry-prod
```

> **Note**: The role name is "Cognitive Services OpenAI User" even for Anthropic models. This is a Foundry quirk — the role governs access to the unified AI endpoint.

### Step 4: Update APIM Named Values

```bash
# Set Foundry endpoint in APIM
az apim nv create \
  --service-name citadel-apim-prod \
  --resource-group citadel-budgets-rg \
  --named-value-id foundry-anthropic-endpoint \
  --display-name "foundry-anthropic-endpoint" \
  --value "$FOUNDRY_ENDPOINT/anthropic/v1"

# Optional: If using API key mode instead of MI
az apim nv create \
  --service-name citadel-apim-prod \
  --resource-group citadel-budgets-rg \
  --named-value-id foundry-api-key \
  --display-name "foundry-api-key" \
  --value "<key-from-foundry-portal>" \
  --secret true
```

### Step 5: Verify Foundry Connectivity

Test direct call to Foundry (bypassing APIM, for validation only):

```bash
# Get an Entra token for Cognitive Services scope
TOKEN=$(az account get-access-token \
  --resource https://cognitiveservices.azure.com \
  --query accessToken -o tsv)

# Call Foundry Anthropic endpoint
curl -X POST "$FOUNDRY_ENDPOINT/anthropic/v1/messages" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 50
  }'
```

**Expected response**:
```json
{
  "id": "msg_...",
  "type": "message",
  "role": "assistant",
  "content": [{"type": "text", "text": "Hello! How can I help you today?"}],
  "model": "claude-sonnet-4-5",
  "usage": {
    "input_tokens": 8,
    "output_tokens": 12
  }
}
```

---

## 5. Foundry-Specific Considerations for Citadel

### Deployment Naming in Telemetry

The `model` field in the request becomes the `deploymentName` in our Event Hub telemetry schema. Ensure consistency:

| Source | Field | Example Value |
|--------|-------|---------------|
| Claude Code request | `body.model` | `"claude-sonnet-4-5"` |
| APIM context variable | `context.Variables["model"]` | `"claude-sonnet-4-5"` |
| Event Hub message | `deploymentName` | `"claude-sonnet-4-5"` |
| Cosmos ai-usage doc | `deploymentName` | `"claude-sonnet-4-5"` |
| Power BI slicer | Model dimension | `claude-sonnet-4-5` |

**Implication**: If your Foundry deployments use non-standard names, every downstream consumer (Logic App, PBIX, budget policies) must be updated to recognize them.

### Token Counting

Foundry returns token counts in the Anthropic format:

```json
"usage": {
  "input_tokens": 142,
  "output_tokens": 89
}
```

Our usage fragments map these to the existing Event Hub schema:

```javascript
{
  "promptTokens": 142,      // ← usage.input_tokens
  "responseTokens": 89,     // ← usage.output_tokens
  "totalTokens": 231        // ← sum
}
```

This mapping is hardcoded in [`frag-citadel-anthropic-usage.xml`](../bicep/infra/modules/apim/policies/frag-citadel-anthropic-usage.xml).

### Streaming Completion

Foundry's SSE stream for Anthropic models matches the upstream Anthropic API:

```
event: message_start
data: {"type":"message_start", ...}

event: content_block_delta
data: {"type":"content_block_delta", "delta":{"type":"text_delta","text":"Hello"}}

event: message_delta
data: {"type":"message_delta", "usage":{"output_tokens":42}}

event: message_stop
data: {"type":"message_stop"}
```

**Critical**: The **terminal `message_delta` event** carries `usage.output_tokens`. Our streaming fragment ([`frag-citadel-anthropic-usage-streaming.xml`](../bicep/infra/modules/apim/policies/frag-citadel-anthropic-usage-streaming.xml)) must parse this event to emit accurate token telemetry.

### Billing and Credits

- **Azure Free Credits**: Some Azure free credits **do not cover** third-party (Anthropic) models in Foundry. Check your subscription's credit terms.
- **Foundry Metering**: Usage is metered at the Foundry deployment level and appears under the Foundry resource in Azure Cost Management.
- **Citadel Budget**: Our budgets are **token-based**, not cost-based (POC scope). Cost conversion happens in Power BI via a model-pricing lookup table.

---

## 6. Differences from Direct Anthropic API

| Aspect | Direct Anthropic API | Foundry-Hosted Anthropic |
|--------|----------------------|--------------------------|
| **Base URL** | `https://api.anthropic.com` | `https://<foundry>.api.foundry.ml.azure.com/anthropic/v1` |
| **Authentication** | `x-api-key: sk-ant-...` | `Authorization: Bearer <azure-ad-token>` or `x-api-key: <foundry-key>` |
| **Model Names** | `claude-3-5-sonnet-20241022` | Deployment name (e.g., `claude-sonnet-4-5`) |
| **Billing** | Anthropic account | Azure subscription |
| **Regional Deployment** | Anthropic-managed | Azure region of your choice |
| **Response Format** | Identical JSON | Identical JSON (Foundry is API-compatible) |
| **Streaming** | Identical SSE | Identical SSE |
| **SDK Support** | Official Anthropic SDK | Anthropic SDK with `base_url` override |

**Citadel Implication**: Developers who have used Anthropic's API directly will recognize the request/response shape. The only changes are `ANTHROPIC_BASE_URL` and authentication mode.

---

## 7. Integration Checklist for APIM Policy Authors

When updating Citadel's Anthropic API policies, verify:

- [ ] Foundry endpoint URL ends with `/anthropic/v1` (no trailing slash before appending `/messages`)
- [ ] Managed Identity token requests `resource="https://cognitiveservices.azure.com"`, not `resource="https://foundry.ml.azure.com"`
- [ ] User's `Authorization` header is **stripped** before forwarding to Foundry (D1 requirement)
- [ ] `model` field from request body is captured for telemetry **before** request is proxied
- [ ] Streaming responses parse the **`message_delta` event** to extract final `usage.output_tokens`
- [ ] Token counts are mapped to existing Event Hub schema (`promptTokens`, `responseTokens`, `totalTokens`)
- [ ] Deployment names in APIM Named Values match Foundry deployment names exactly (case-sensitive)

---

## References

- [Microsoft TechCommunity Blog: Giving developers Claude Code with Azure API Management](https://techcommunity.microsoft.com/blog/azure-ai-foundry-blog/giving-developers-claude-code-with-azure-api-management-and-claude-models-in-mic/4525212)
- [Microsoft Learn: Deploy and use Claude models in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/ai-services/foundry/deploy-anthropic-claude)
- [Anthropic API Reference: Messages API](https://docs.anthropic.com/en/api/messages)
- [Claude Code GitHub Setup Guide](https://github.com/xomicsdatascience/ClaudeCode_with_Azure)
- Citadel plan: [.github/prompts/plan-citadelBudgets.prompt.md](../.github/prompts/plan-citadelBudgets.prompt.md)
