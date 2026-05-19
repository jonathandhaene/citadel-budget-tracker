using './main.citadel.bicep'

// Development environment - small limits for testing
param environmentName = 'dev'
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

// Monthly token budgets (DEV: small for fast iteration)
param tierBudgets = {
  bronze: {
    monthlyTokenLimit: 10000        // 10k tokens (~5 medium requests)
    models: {
      'claude-sonnet-4': 10000
      'claude-opus-4': 5000         // Lower for expensive model
    }
  }
  silver: {
    monthlyTokenLimit: 50000        // 50k tokens
    models: {
      'claude-sonnet-4': 50000
      'claude-opus-4': 25000
    }
  }
  gold: {
    monthlyTokenLimit: 200000       // 200k tokens
    models: {
      'claude-sonnet-4': 200000
      'claude-opus-4': 100000
    }
  }
}

// Cosmos DB configuration
param cosmosDbConfig = {
  accountName: 'citadel-budgets-dev-cosmos'
  databaseName: 'ai-usage-db'
  throughput: 400                   // Minimum for dev
  enableFreeTier: true              // Use free tier if available
}

// APIM configuration
param apimConfig = {
  name: 'citadel-budgets-dev-apim'
  sku: 'Developer'                  // Developer tier for dev environment
  skuCapacity: 1
  publisherEmail: 'dev-team@contoso.com'
  publisherName: 'Contoso Dev Team'
}

// Monitoring configuration
param monitoring = {
  logAnalyticsWorkspaceName: 'citadel-budgets-dev-logs'
  applicationInsightsName: 'citadel-budgets-dev-insights'
  enableAlerts: false               // Disable alerts in dev to reduce noise
  dataRetentionDays: 30
}

// tier-sync Function configuration
param tierSyncConfig = {
  functionAppName: 'citadel-tier-sync-dev'
  schedule: '0 0 */6 * * *'         // Every 6 hours
  enableDeadLetterQueue: true
}

// Foundry backend configuration
param foundryBackend = {
  endpoint: '<foundry-anthropic-endpoint>'  // Replace with your Foundry endpoint
  deploymentName: 'claude-sonnet-4-deployment'
}

// Tags
param tags = {
  Environment: 'Development'
  Project: 'Citadel Budgets'
  ManagedBy: 'Bicep'
  CostCenter: 'AI-CoE'
}
