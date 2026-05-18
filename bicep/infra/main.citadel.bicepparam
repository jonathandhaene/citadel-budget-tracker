using './main.citadel.bicep'

// ============================================================================
// Citadel Budgets — parameter file (paper-only placeholders)
// ============================================================================
// Replace every `<...>` placeholder with real values before deploying.
// See `CITADEL-OVERLAY.md` §"Customer review checklist" for the 6 inputs the customer must supply.

// --- Existing upstream resources (resolved from the upstream `azd up` output) ---
param apimName            = '<apim-name-from-upstream>'
param cosmosAccountName   = '<cosmos-account-name-from-upstream>'

// --- The 6 customer-supplied inputs ---
param customerTenantId        = '<customer-tenant-id>'
param claudeCodeAppId            = '<claude-code-app-id>'
param foundryAnthropicEndpoint   = '<foundry-anthropic-endpoint>'
param claudeDeploymentName       = '<claude-deployment-name>'

param tierGroupMap = {
  bronze: '<tier-group-oid-bronze>'
  silver: '<tier-group-oid-silver>'
  gold:   '<tier-group-oid-gold>'
}

// --- Tier limits (defaults shown; AI governance council to ratify) ---
param tierMonthlyTokenLimits = {
  bronze: 200000
  silver: 1000000
  gold:   5000000
}

param goldPerModel = {
  'claude-opus-4': 2000000
}

// --- Tier-sync Function hosting (point at existing or newly-created resources) ---
param tierSyncAppServicePlanId             = '<app-service-plan-resource-id>'
param tierSyncStorageAccountName           = '<storage-account-name>'
param tierSyncAppInsightsConnectionString  = '<app-insights-connection-string>'
param tierSyncFunctionAppName              = 'fa-citadel-tier-sync'

// --- Cosmos data-plane MI used by budget-seed deploymentScripts ---
param dataPlaneIdentityResourceId          = '<user-assigned-mi-resource-id-with-cosmos-data-contrib>'
