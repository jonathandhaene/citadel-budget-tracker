// Tier contract: GOLD
// High-volume tier with per-model carve-outs (e.g. cap Opus separately because $/token is highest).

@description('Cosmos DB account name.')
param cosmosAccountName string

@description('User-assigned MI with Cosmos data plane write permission.')
param dataPlaneIdentityResourceId string

@description('Wildcard monthly token cap (applies to any model not explicitly carved out). Placeholder.')
param goldMonthlyTokenLimit int = 5000000

@description('Per-model carve-outs. Each carve-out becomes its own (tier:gold:<model>) doc with higher precedence than the wildcard.')
param goldPerModel object = {
  'claude-opus-4': 2000000
}

@description('Entra group object ID whose transitive members get gold tier.')
param goldGroupOid string = '<tier-group-oid-gold>'

// Wildcard (tier:gold:*)
module goldWildcard '../_shared/budget-seed.bicep' = {
  name: 'budget-tier-gold-wildcard'
  params: {
    cosmosAccountName: cosmosAccountName
    dataPlaneIdentityResourceId: dataPlaneIdentityResourceId
    scope: 'tier:gold:*'
    monthlyTokenLimit: goldMonthlyTokenLimit
    note: 'Gold tier default budget. Citadel Access Contract — gold.bicep.'
  }
}

// Per-model carve-outs (one budget doc per entry — higher precedence than wildcard).
module goldPerModelBudgets '../_shared/budget-seed.bicep' = [for model in items(goldPerModel): {
  name: 'budget-tier-gold-${replace(model.key, ".", "-")}'
  params: {
    cosmosAccountName: cosmosAccountName
    dataPlaneIdentityResourceId: dataPlaneIdentityResourceId
    scope: 'tier:gold:${model.key}'
    monthlyTokenLimit: model.value
    note: 'Gold tier per-model carve-out for ${model.key}.'
  }
}]

output tier string = 'gold'
output groupOid string = goldGroupOid
