// Example per-user override contract (Citadel Access Contract — D5).
//
// Use cases:
//   - Researcher needs higher cap than gold for a specific model for one quarter.
//   - VIP user with adminOverride=true (no enforcement at all — emergency-only).
//   - Specific model carve-out that supersedes the user's tier wildcard.
//
// Precedence reminder (D2):
//   (oid, model)  ─ highest
//   (oid, *)
//   (tier, model)
//   (tier, *)
//   global:*:*    ─ lowest
//
// EACH OVERRIDE IS ITS OWN PR. The Bicep commit history is the audit trail (no audit-log container in POC).

@description('Cosmos account.')
param cosmosAccountName string

@description('Cosmos data-plane MI.')
param dataPlaneIdentityResourceId string

@description('Target user OID — from Entra portal. NOT a UPN. NOT a display name.')
param targetUserOid string = '<placeholder-oid>'

@description('Approval note. Include ticket ID, approver, and expiry plan.')
param approvalNote string = 'EXAMPLE — replace with real approval ticket #.'

// Example 1: Boost claude-opus-4 specifically for this user above gold tier carve-out.
module userOpusOverride '../_shared/budget-seed.bicep' = {
  name: 'budget-user-${targetUserOid}-opus'
  params: {
    cosmosAccountName: cosmosAccountName
    dataPlaneIdentityResourceId: dataPlaneIdentityResourceId
    scope: 'user:${targetUserOid}:claude-opus-4'
    monthlyTokenLimit: 5000000
    note: approvalNote
  }
}

// Example 2 (commented out — illustrative): adminOverride bypass for a single user.
// module userAdminOverride '../_shared/budget-seed.bicep' = {
//   name: 'budget-user-${targetUserOid}-bypass'
//   params: {
//     cosmosAccountName: cosmosAccountName
//     dataPlaneIdentityResourceId: dataPlaneIdentityResourceId
//     scope: 'user:${targetUserOid}:*'
//     monthlyTokenLimit: 0
//     adminOverride: true
//     note: 'EMERGENCY ONLY — ticket #1234. Auto-expires by manual revert PR by 2026-06-30.'
//   }
// }
