// Overlay note for `_upstream/bicep/infra/modules/apim/apim.bicep`.
// Citadel does NOT rewrite the upstream file — it inserts these resources additively.
// At deploy time, the Citadel orchestrator (`main.citadel.bicep`) references the existing APIM
// and creates the resources below alongside it.

# `apim.bicep` overlay patch (illustrative — not copy-paste-ready)

Upstream `apim.bicep` (around line ~726) registers policy fragments in a loop. Citadel adds four fragments and three Named Values to that block.

## New policy fragments

```bicep
// Citadel additions — append to the upstream fragment-registration block.
resource fragCitadelAnthropicAuth 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apim
  name: 'citadel-anthropic-auth'
  properties: {
    description: 'Citadel: Entra JWT validation for Claude Code (v2.0 issuer, captures oid/upn).'
    format: 'rawxml'
    value: loadTextContent('./policies/frag-citadel-anthropic-auth.xml')
  }
}

resource fragCitadelAnthropicUsage 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apim
  name: 'citadel-anthropic-usage'
  properties: {
    description: 'Citadel: Anthropic non-streaming usage emit to Event Hub.'
    format: 'rawxml'
    value: loadTextContent('./policies/frag-citadel-anthropic-usage.xml')
  }
}

resource fragCitadelAnthropicUsageStreaming 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apim
  name: 'citadel-anthropic-usage-streaming'
  properties: {
    description: 'Citadel: Anthropic SSE streaming usage emit (terminal message_delta).'
    format: 'rawxml'
    value: loadTextContent('./policies/frag-citadel-anthropic-usage-streaming.xml')
  }
}

resource fragCitadelBudgetCheck 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apim
  name: 'citadel-budget-check'
  properties: {
    description: 'Citadel: D2/D3/D4 per-user×per-model budget precedence + cache + 429 enforcement.'
    format: 'rawxml'
    value: loadTextContent('./policies/frag-citadel-budget-check.xml')
  }
}
```

## New Named Values (referenced from `anthropic-api-policy.xml`)

| Name | Sourced from | Example |
|------|--------------|---------|
| `claude-code-app-id` | `main.citadel.bicepparam` param `claudeCodeAppId` | `<claude-code-app-id>` |
| `customer-tenant-id` | `main.citadel.bicepparam` param `customerTenantId` | `<customer-tenant-id>` |
| `citadel-cosmos-budgets-url` | Output of `cosmos-db.citadel.bicep` | `https://<acct>.documents.azure.com/dbs/ai-usage-db/colls/budgets` |
| `citadel-cosmos-user-tier-url` | Output of `cosmos-db.citadel.bicep` | `https://<acct>.documents.azure.com/dbs/ai-usage-db/colls/user-tier` |
| `citadel-cosmos-usage-url` | Output of `cosmos-db.citadel.bicep` | `https://<acct>.documents.azure.com/dbs/ai-usage-db/colls/ai-usage-monthly` |
| `citadel-cosmos-auth-header` | Set at runtime via `authentication-managed-identity` — see budget-check fragment | (computed) |

```bicep
resource nvClaudeCodeAppId 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'claude-code-app-id'
  properties: {
    displayName: 'claude-code-app-id'
    value: claudeCodeAppId  // from main.citadel.bicepparam
    secret: false
  }
}
// ...same pattern for customer-tenant-id, citadel-cosmos-*-url ...
```

## API registration

```bicep
module anthropicApi './anthropic/anthropic-api.bicep' = {
  name: 'citadel-anthropic-api'
  params: {
    apimName: apim.name
    apiPath: 'anthropic'
    foundryAnthropicEndpoint: foundryAnthropicEndpoint
    claudeDeploymentName: claudeDeploymentName
  }
  dependsOn: [
    fragCitadelAnthropicAuth
    fragCitadelAnthropicUsage
    fragCitadelAnthropicUsageStreaming
    fragCitadelBudgetCheck
    nvClaudeCodeAppId
    // ...other Named Values
  ]
}
```
