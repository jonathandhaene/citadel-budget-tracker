using './main.bicep'

// Placeholder values — replaced at deploy time by the customer.
// (This file is illustrative; the real param file lives next to main.citadel.bicep.)

param cosmosAccountName    = '<cosmos-account-name>'
param dataPlaneIdentityId  = '<data-plane-user-assigned-mi-resource-id>'

param tierGroupMap = {
  bronze: '<tier-group-oid-bronze>'
  silver: '<tier-group-oid-silver>'
  gold:   '<tier-group-oid-gold>'
}

param tierMonthlyTokenLimits = {
  bronze: 200000
  silver: 1000000
  gold:   5000000
}

param goldPerModel = {
  'claude-opus-4': 2000000
}
