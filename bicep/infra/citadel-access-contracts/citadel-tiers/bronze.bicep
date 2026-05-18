// Tier contract: BRONZE
// Default Citadel tier. Assigned automatically by tier-sync Function when an Entra OID is not a
// member of any higher-tier group. Cannot be removed.

@description('Cosmos DB account name (from cosmos-db.citadel.bicep).')
param cosmosAccountName string

@description('User-assigned MI with Cosmos data plane write permission.')
param dataPlaneIdentityResourceId string

@description('Monthly token cap for bronze tier. Placeholder.')
param bronzeMonthlyTokenLimit int = 200000

@description('Entra group object ID whose transitive members get bronze tier. Empty = default fallback (no explicit membership required).')
param bronzeGroupOid string = '<tier-group-oid-bronze>'

module bronzeWildcard '../_shared/budget-seed.bicep' = {
  name: 'budget-tier-bronze-wildcard'
  params: {
    cosmosAccountName: cosmosAccountName
    dataPlaneIdentityResourceId: dataPlaneIdentityResourceId
    scope: 'tier:bronze:*'
    monthlyTokenLimit: bronzeMonthlyTokenLimit
    note: 'Bronze tier default budget. Citadel Access Contract — bronze.bicep.'
  }
}

output tier string = 'bronze'
output groupOid string = bronzeGroupOid
