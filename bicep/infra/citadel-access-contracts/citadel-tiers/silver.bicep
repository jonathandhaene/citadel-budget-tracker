// Tier contract: SILVER
// Standard production tier for active Claude Code users.

@description('Cosmos DB account name.')
param cosmosAccountName string

@description('User-assigned MI with Cosmos data plane write permission.')
param dataPlaneIdentityResourceId string

@description('Monthly token cap for silver tier. Placeholder.')
param silverMonthlyTokenLimit int = 1000000

@description('Entra group object ID whose transitive members get silver tier.')
param silverGroupOid string = '<tier-group-oid-silver>'

module silverWildcard '../_shared/budget-seed.bicep' = {
  name: 'budget-tier-silver-wildcard'
  params: {
    cosmosAccountName: cosmosAccountName
    dataPlaneIdentityResourceId: dataPlaneIdentityResourceId
    scope: 'tier:silver:*'
    monthlyTokenLimit: silverMonthlyTokenLimit
    note: 'Silver tier default budget. Citadel Access Contract — silver.bicep.'
  }
}

output tier string = 'silver'
output groupOid string = silverGroupOid
