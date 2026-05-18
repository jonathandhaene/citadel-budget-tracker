// Bicep module: Citadel tier-sync Function App
// Deploys: Function App (Linux, Node 20), MI, Cosmos data-contributor role, App settings.
// Graph permission grants must be done out-of-band (PowerShell / portal) — Bicep cannot grant
// admin consent. The deploy README calls this out.

@description('Function App name (must be globally unique).')
param functionAppName string

@description('App Service plan to host the function (Linux consumption or Flex Consumption).')
param appServicePlanId string

@description('Storage account name for Function App runtime.')
param storageAccountName string

@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Cosmos account hosting ai-usage-db.')
param cosmosAccountName string

@description('Entra tier-group OIDs.')
param tierGroupMap object

@description('Location.')
param location string = resourceGroup().location

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-08-15' existing = {
  name: cosmosAccountName
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|20'
      appSettings: [
        { name: 'AzureWebJobsStorage__accountName', value: storage.name }
        { name: 'FUNCTIONS_EXTENSION_VERSION',     value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME',         value: 'node' }
        { name: 'WEBSITE_NODE_DEFAULT_VERSION',     value: '~20' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
        { name: 'COSMOS_ACCOUNT_NAME',              value: cosmosAccountName }
        { name: 'TIER_GROUP_OID_BRONZE',            value: tierGroupMap.bronze }
        { name: 'TIER_GROUP_OID_SILVER',            value: tierGroupMap.silver }
        { name: 'TIER_GROUP_OID_GOLD',              value: tierGroupMap.gold }
      ]
    }
  }
}

// Cosmos data-contributor role for the Function MI (data plane RBAC, NOT control-plane RBAC).
resource cosmosDataContribDefinition 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2024-08-15' existing = {
  parent: cosmos
  // Built-in 'Cosmos DB Built-in Data Contributor' role
  name: '00000000-0000-0000-0000-000000000002'
}

resource cosmosRoleAssign 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-08-15' = {
  parent: cosmos
  name: guid(cosmos.id, functionApp.id, 'tier-sync-data-contrib')
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: cosmosDataContribDefinition.id
    scope: cosmos.id
  }
}

output functionAppPrincipalId string = functionApp.identity.principalId
output functionAppName string = functionApp.name

// IMPORTANT: After this Bicep runs, you MUST grant Graph permissions to the Function MI:
//   az ad sp show --id <functionAppPrincipalId>
//   # then assign Group.Read.All and Directory.Read.All (Application permissions)
//   # and admin-consent them. See README.md.
