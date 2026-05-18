// Tier contracts orchestrator — deploys bronze + silver + gold contracts in one shot.

param cosmosAccountName string
param dataPlaneIdentityId string
param tierGroupMap object
param tierMonthlyTokenLimits object
param goldPerModel object

module bronze './bronze.bicep' = {
  name: 'citadel-tier-bronze'
  params: {
    cosmosAccountName: cosmosAccountName
    dataPlaneIdentityResourceId: dataPlaneIdentityId
    bronzeMonthlyTokenLimit: tierMonthlyTokenLimits.bronze
    bronzeGroupOid: tierGroupMap.bronze
  }
}

module silver './silver.bicep' = {
  name: 'citadel-tier-silver'
  params: {
    cosmosAccountName: cosmosAccountName
    dataPlaneIdentityResourceId: dataPlaneIdentityId
    silverMonthlyTokenLimit: tierMonthlyTokenLimits.silver
    silverGroupOid: tierGroupMap.silver
  }
}

module gold './gold.bicep' = {
  name: 'citadel-tier-gold'
  params: {
    cosmosAccountName: cosmosAccountName
    dataPlaneIdentityResourceId: dataPlaneIdentityId
    goldMonthlyTokenLimit: tierMonthlyTokenLimits.gold
    goldPerModel: goldPerModel
    goldGroupOid: tierGroupMap.gold
  }
}

output tierGroupMap object = {
  bronze: bronze.outputs.groupOid
  silver: silver.outputs.groupOid
  gold:   gold.outputs.groupOid
}
