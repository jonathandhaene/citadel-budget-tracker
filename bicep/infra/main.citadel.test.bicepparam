using './main.citadel.bicep'

// Test environment - minimal limits for fast validation
param environmentName = 'test'
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

// Monthly token budgets (TEST: 1-token limits for fast iteration)
// This allows testing budget exhaustion after a single request
param tierBudgets = {
  bronze: {
    monthlyTokenLimit: 1            // 1 token - instant exhaustion
    models: {
      'claude-sonnet-4': 1
      'claude-opus-4': 1
    }
  }
  silver: {
    monthlyTokenLimit: 10           // 10 tokens - exhausted after ~1 request
    models: {
      'claude-sonnet-4': 10
      'claude-opus-4': 10
    }
  }
  gold: {
    monthlyTokenLimit: 100          // 100 tokens - exhausted after ~3 requests
    models: {
      'claude-sonnet-4': 100
      'claude-opus-4': 100
    }
  }
}

// Cosmos DB configuration
param cosmosDbConfig = {
  accountName: 'citadel-budgets-test-cosmos'
  databaseName: 'ai-usage-db'
  throughput: 400                   // Minimum for test
  enableFreeTier: true              // Use free tier if available
}

// APIM configuration
param apimConfig = {
  name: 'citadel-budgets-test-apim'
  sku: 'Developer'                  // Developer tier for test environment
  skuCapacity: 1
  publisherEmail: 'test-team@contoso.com'
  publisherName: 'Contoso Test Team'
}

// Monitoring configuration
param monitoring = {
  logAnalyticsWorkspaceName: 'citadel-budgets-test-logs'
  applicationInsightsName: 'citadel-budgets-test-insights'
  enableAlerts: false               // Disable alerts in test
  dataRetentionDays: 7              // Minimal retention for test
}

// tier-sync Function configuration
param tierSyncConfig = {
  functionAppName: 'citadel-tier-sync-test'
  schedule: '0 */15 * * * *'        // Every 15 minutes for faster testing
  enableDeadLetterQueue: true
}

// Foundry backend configuration
param foundryBackend = {
  endpoint: '<foundry-anthropic-endpoint>'  // Replace with your Foundry endpoint
  deploymentName: 'claude-sonnet-4-deployment'
}

// Tags
param tags = {
  Environment: 'Test'
  Project: 'Citadel Budgets'
  ManagedBy: 'Bicep'
  CostCenter: 'AI-CoE'
  AutoDelete: 'true'                // Indicate this can be auto-deleted
}

// Test-specific configuration
param testConfig = {
  enableVerboseLogging: true        // Extra logging for debugging
  cacheTTL: 10                      // 10 seconds cache for faster testing
  enableDebugHeaders: true          // Include debug info in responses
}
