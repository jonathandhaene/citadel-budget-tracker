// Shared helper: upsert a Citadel budget document into the `budgets` Cosmos container.
// Used by every tier contract and every per-user override.
//
// Paper-only: this module wraps a deploymentScript that POSTs to Cosmos REST. In production
// you would prefer Microsoft.DocumentDB sqlRoleAssignment + a Function or simply a deployment
// script with AzCLI + cosmos extension. The placeholder script body below is illustrative.

@description('Cosmos DB account name.')
param cosmosAccountName string

@description('Database name. Default: ai-usage-db.')
param databaseName string = 'ai-usage-db'

@description('Container name. Default: budgets.')
param containerName string = 'budgets'

@description('Budget scope identifier. Format examples: tier:gold:*, tier:gold:claude-opus-4, user:<oid>:*, user:<oid>:claude-sonnet-4, global:*:*')
param scope string

@description('Monthly token budget. Use 0 to mean "no limit" — but prefer setting adminOverride=true on a real doc.')
@minValue(0)
param monthlyTokenLimit int

@description('Bypass enforcement entirely for this scope (D4 adminOverride).')
param adminOverride bool = false

@description('Optional per-model overrides for tier-wide scopes. Ignored when scope is user-specific. Shape: { "claude-opus-4": 2000000 }')
param perModelOverrides object = {}

@description('Free-form note recorded with the doc (e.g. "Approved by AI governance council 2026-Q1, ticket #1234").')
param note string = ''

@description('User-assigned managed identity that has Cosmos data plane write permission.')
param dataPlaneIdentityResourceId string

@description('Location for the deployment script resource.')
param location string = resourceGroup().location

var docId = replace(replace(scope, ':', '_'), '/', '_')

resource seedBudget 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'citadel-seed-budget-${docId}'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${dataPlaneIdentityResourceId}': {}
    }
  }
  properties: {
    azCliVersion: '2.61.0'
    timeout: 'PT10M'
    retentionInterval: 'P1D'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      { name: 'COSMOS_ACCOUNT', value: cosmosAccountName }
      { name: 'COSMOS_DB',      value: databaseName }
      { name: 'COSMOS_CTNR',    value: containerName }
      { name: 'DOC_ID',         value: docId }
      { name: 'SCOPE',          value: scope }
      { name: 'LIMIT',          value: string(monthlyTokenLimit) }
      { name: 'ADMIN_OVERRIDE', value: string(adminOverride) }
      { name: 'PER_MODEL',      value: string(perModelOverrides) }
      { name: 'NOTE',           value: note }
    ]
    scriptContent: '''
      set -euo pipefail
      az config set extension.use_dynamic_install=yes_without_prompt
      cat <<EOF > /tmp/budget.json
      {
        "id":     "$DOC_ID",
        "scope":  "$SCOPE",
        "monthlyTokenLimit": $LIMIT,
        "adminOverride": $ADMIN_OVERRIDE,
        "perModelOverrides": $PER_MODEL,
        "note":   "$NOTE",
        "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      }
      EOF
      az cosmosdb sql container ensure --account-name "$COSMOS_ACCOUNT" --database-name "$COSMOS_DB" --name "$COSMOS_CTNR" >/dev/null 2>&1 || true
      # Use cosmosdb data-plane SDK or REST here. Paper-only stub:
      echo "[paper-only] Would upsert budget doc id=$DOC_ID scope=$SCOPE limit=$LIMIT override=$ADMIN_OVERRIDE"
    '''
  }
}

output budgetDocId string = docId
