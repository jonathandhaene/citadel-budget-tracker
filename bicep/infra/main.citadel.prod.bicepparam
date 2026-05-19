using './main.citadel.bicep'

// Production environment - realistic limits
param environmentName = 'prod'
param location = 'eastus'

// Entra ID configuration
param tenantId = '<your-tenant-id>'  // Replace with your Entra tenant ID
param claudeCodeAppId = '<claude-code-app-id>'  // Replace with Anthropic Claude Code app ID

// Tier group mappings (Entra security groups)
param tierGroups = {
  bronze: '<tier-group-oid-bronze>'  // Optional - fallback tier
  silver: '<tier-group-oid-silver>'  // Replace with your silver tier group OID
  gold: '<tier-group-oid-gold>'      // Replace with your gold tier group OID
}

// Monthly token budgets (PROD: realistic for actual usage)
param tierBudgets = {
  bronze: {
    monthlyTokenLimit: 500000       // 500k tokens (~250 medium conversations)
    models: {
      'claude-sonnet-4': 500000
      'claude-opus-4': 250000       // Half for expensive model
    }
  }
  silver: {
    monthlyTokenLimit: 2000000      // 2M tokens (~1000 medium conversations)
    models: {
      'claude-sonnet-4': 2000000
      'claude-opus-4': 1000000
    }
  }
  gold: {
    monthlyTokenLimit: 10000000     // 10M tokens (power users)
    models: {
      'claude-sonnet-4': 10000000
      'claude-opus-4': 5000000
    }
  }
}

// Cosmos DB configuration
param cosmosDbConfig = {
  accountName: 'citadel-budgets-prod-cosmos'
  databaseName: 'ai-usage-db'
  throughput: 4000                  // Autoscale for production
  enableFreeTier: false
  enableBackup: true
  backupIntervalInMinutes: 240      // 4 hours
  backupRetentionIntervalInHours: 720  // 30 days
}

// APIM configuration
param apimConfig = {
  name: 'citadel-budgets-prod-apim'
  sku: 'Standard'                   // Standard tier for production
  skuCapacity: 2                    // 2 units for HA
  publisherEmail: 'ai-coe@contoso.com'
  publisherName: 'Contoso AI Center of Excellence'
  enableZoneRedundancy: true
}

// Monitoring configuration
param monitoring = {
  logAnalyticsWorkspaceName: 'citadel-budgets-prod-logs'
  applicationInsightsName: 'citadel-budgets-prod-insights'
  enableAlerts: true                // Enable all alerts in production
  dataRetentionDays: 90
  enableContinuousExport: true      // Export to Storage for long-term retention
}

// tier-sync Function configuration
param tierSyncConfig = {
  functionAppName: 'citadel-tier-sync-prod'
  schedule: '0 0 */6 * * *'         // Every 6 hours
  enableDeadLetterQueue: true
  maxRetryAttempts: 3
}

// Foundry backend configuration
param foundryBackend = {
  endpoint: '<foundry-anthropic-endpoint>'  // Replace with your Foundry endpoint
  deploymentName: 'claude-sonnet-4-deployment'
  enableMultiRegion: true
  secondaryEndpoint: '<foundry-anthropic-endpoint-secondary>'
}

// Security configuration
param security = {
  enableCosmosFirewall: true
  allowedSubnets: [
    '<apim-subnet-id>'
    '<tier-sync-function-subnet-id>'
  ]
  enablePrivateEndpoints: true
  enableDefender: true              // Microsoft Defender for Cloud
}

// Tags
param tags = {
  Environment: 'Production'
  Project: 'Citadel Budgets'
  ManagedBy: 'Bicep'
  CostCenter: 'AI-CoE'
  Criticality: 'High'
  DataClassification: 'Confidential'
}
