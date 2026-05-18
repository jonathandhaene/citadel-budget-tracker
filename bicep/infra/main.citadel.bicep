// =============================================================================
// Citadel Budgets — top-level orchestrator (overlay on `_upstream/main.bicep`)
// =============================================================================
// This file orchestrates ONLY the Citadel deltas. It assumes the upstream Citadel
// Governance Hub (`bicep/infra/main.bicep` from `citadel-v1`) has already deployed:
//   - APIM service
//   - Cosmos DB account + `ai-usage-db` database
//   - Event Hub namespace + `usage-eventhub-logger`
//   - Logic App (ai-usage-ingestion)
//
// Run order (paper-only — production uses azd):
//   1) `azd up` against upstream branch → produces APIM, Cosmos, Event Hub, Logic App.
//   2) `az deployment sub create -f main.citadel.bicep -p main.citadel.bicepparam` → adds Citadel overlay.
//
// See `CITADEL-OVERLAY.md` at repo root for the customer-facing walkthrough.
// =============================================================================

targetScope = 'resourceGroup'

// ----- Required from upstream -----
@description('APIM service name (existing, from upstream deploy).')
param apimName string

@description('Cosmos DB account name (existing).')
param cosmosAccountName string

@description('Resource group of upstream deploy. Defaults to current.')
param upstreamResourceGroup string = resourceGroup().name

// ----- customer-supplied (6 inputs) -----
@description('customer Entra tenant ID.')
param customerTenantId string

@description('Claude Code Anthropic-published Entra app ID — the JWT audience (D1).')
param claudeCodeAppId string

@description('Foundry Anthropic backend URL (e.g. https://<resource>.openai.azure.com or Foundry-specific endpoint).')
param foundryAnthropicEndpoint string

@description('Foundry deployment name for the Claude model (e.g. claude-sonnet-4).')
param claudeDeploymentName string

@description('Entra group OIDs per tier — populated by customer IAM team.')
param tierGroupMap object = {
  bronze: '<tier-group-oid-bronze>'
  silver: '<tier-group-oid-silver>'
  gold:   '<tier-group-oid-gold>'
}

@description('Monthly token limits per tier.')
param tierMonthlyTokenLimits object = {
  bronze: 200000
  silver: 1000000
  gold:   5000000
}

@description('Per-model carve-outs inside gold tier.')
param goldPerModel object = {
  'claude-opus-4': 2000000
}

// ----- Function App hosting for tier-sync -----
@description('App Service plan for the tier-sync Function.')
param tierSyncAppServicePlanId string

@description('Storage account for the tier-sync Function runtime.')
param tierSyncStorageAccountName string

@description('Application Insights connection string for the tier-sync Function.')
param tierSyncAppInsightsConnectionString string

@description('Tier-sync Function App name.')
param tierSyncFunctionAppName string = 'fa-citadel-tier-sync'

@description('User-assigned MI used by deployment-scripts to write Cosmos data plane.')
param dataPlaneIdentityResourceId string

@description('Location.')
param location string = resourceGroup().location

// ============================================================================
// 1. Cosmos containers (budgets, user-tier, ai-usage-monthly)
// ============================================================================
module cosmosCitadel './modules/cosmos-db/cosmos-db.citadel.bicep' = {
  name: 'citadel-cosmos-containers'
  params: {
    accountName: cosmosAccountName
  }
}

// ============================================================================
// 2. APIM Citadel overlay (fragments + Named Values + Anthropic API)
//    NOTE: Patch detail is in `modules/apim/apim.citadel-patch.md`.
//    Below is the minimum new resources added directly here for clarity.
// ============================================================================
resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource fragAuth 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apim
  name: 'citadel-anthropic-auth'
  properties: {
    description: 'Citadel: Entra JWT validation for Claude Code.'
    format: 'rawxml'
    value: loadTextContent('./modules/apim/policies/frag-citadel-anthropic-auth.xml')
  }
}

resource fragUsage 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apim
  name: 'citadel-anthropic-usage'
  properties: {
    description: 'Citadel: Anthropic non-streaming usage emit.'
    format: 'rawxml'
    value: loadTextContent('./modules/apim/policies/frag-citadel-anthropic-usage.xml')
  }
}

resource fragUsageStream 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apim
  name: 'citadel-anthropic-usage-streaming'
  properties: {
    description: 'Citadel: Anthropic SSE streaming usage emit.'
    format: 'rawxml'
    value: loadTextContent('./modules/apim/policies/frag-citadel-anthropic-usage-streaming.xml')
  }
}

resource fragBudget 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apim
  name: 'citadel-budget-check'
  properties: {
    description: 'Citadel: D2/D3/D4 budget enforcement.'
    format: 'rawxml'
    value: loadTextContent('./modules/apim/policies/frag-citadel-budget-check.xml')
  }
}

// Named Values consumed by anthropic-api-policy.xml
var namedValues = [
  { name: 'customer-tenant-id',         value: customerTenantId }
  { name: 'claude-code-app-id',            value: claudeCodeAppId }
  { name: 'citadel-cosmos-budgets-url',    value: cosmosCitadel.outputs.budgetsContainerUrl }
  { name: 'citadel-cosmos-user-tier-url',  value: cosmosCitadel.outputs.userTierContainerUrl }
  { name: 'citadel-cosmos-usage-url',      value: cosmosCitadel.outputs.usageContainerUrl }
]

resource nv 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = [for n in namedValues: {
  parent: apim
  name: n.name
  properties: {
    displayName: n.name
    value: n.value
    secret: false
  }
}]

// Cosmos auth header is set at runtime via authentication-managed-identity — placeholder NV so the
// policy reference resolves at deploy time. The actual bearer is built by the inbound API policy
// before include-fragment "citadel-budget-check" runs (paper-only stub here).
resource nvCosmosAuth 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'citadel-cosmos-auth-header'
  properties: {
    displayName: 'citadel-cosmos-auth-header'
    value: 'Bearer __computed_at_runtime__'
    secret: true
  }
}

// Anthropic API + backend + API-level policy.
module anthropicApi './modules/apim/anthropic/anthropic-api.bicep' = {
  name: 'citadel-anthropic-api'
  params: {
    apimName: apimName
    apiPath: 'anthropic'
    foundryAnthropicEndpoint: foundryAnthropicEndpoint
    claudeDeploymentName: claudeDeploymentName
  }
  dependsOn: [
    fragAuth
    fragUsage
    fragUsageStream
    fragBudget
    nv
    nvCosmosAuth
  ]
}

// ============================================================================
// 3. Citadel Access Contracts — tier contracts (bronze + silver + gold)
// ============================================================================
module tierContracts './citadel-access-contracts/citadel-tiers/main.bicep' = {
  name: 'citadel-tier-contracts'
  params: {
    cosmosAccountName: cosmosAccountName
    dataPlaneIdentityId: dataPlaneIdentityResourceId
    tierGroupMap: tierGroupMap
    tierMonthlyTokenLimits: tierMonthlyTokenLimits
    goldPerModel: goldPerModel
  }
  dependsOn: [
    cosmosCitadel
  ]
}

// ============================================================================
// 4. Tier-sync Function
// ============================================================================
module tierSync '../../src/tier-sync-function/tier-sync-function.bicep' = {
  name: 'citadel-tier-sync-function'
  params: {
    functionAppName: tierSyncFunctionAppName
    appServicePlanId: tierSyncAppServicePlanId
    storageAccountName: tierSyncStorageAccountName
    appInsightsConnectionString: tierSyncAppInsightsConnectionString
    cosmosAccountName: cosmosAccountName
    tierGroupMap: tierGroupMap
    location: location
  }
  dependsOn: [
    cosmosCitadel
  ]
}

// ============================================================================
// Outputs — for the validation notebooks
// ============================================================================
output anthropicApiBase string = 'https://${apim.properties.gatewayUrl}/anthropic'
output budgetsContainerUrl  string = cosmosCitadel.outputs.budgetsContainerUrl
output userTierContainerUrl string = cosmosCitadel.outputs.userTierContainerUrl
output usageContainerUrl    string = cosmosCitadel.outputs.usageContainerUrl
output tierSyncFunctionPrincipalId string = tierSync.outputs.functionAppPrincipalId
