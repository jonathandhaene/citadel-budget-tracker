// Cosmos DB extension for Citadel: adds three containers to the existing `ai-usage-db` database.
// Run AFTER `_upstream/bicep/infra/modules/cosmos-db/cosmos-db.bicep`. Idempotent.
//
// Containers added:
//   budgets           PK /scope     — Citadel Access Contract budget docs (tier + per-user × model).
//   user-tier         PK /oid       — Entra OID -> tier mapping, written by tier-sync Function.
//   ai-usage-monthly  PK /oid       — Monthly per-user × per-model token counter.
//                                      Doc id = "<oid>:<YYYY-MM>:<model>". Logic App is the writer.

@description('Cosmos DB account name (existing, deployed by upstream cosmos-db.bicep).')
param accountName string

@description('Database name (existing). Defaults to upstream `ai-usage-db`.')
param databaseName string = 'ai-usage-db'

@description('Container throughput (shared autoscale strongly recommended at the DB level for POC; per-container manual here for clarity).')
@minValue(400)
@maxValue(4000)
param containerThroughput int = 400

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-08-15' existing = {
  name: accountName
}
resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-08-15' existing = {
  parent: account
  name: databaseName
}

// ------------- budgets -------------
resource budgetsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-08-15' = {
  parent: database
  name: 'budgets'
  properties: {
    resource: {
      id: 'budgets'
      partitionKey: {
        paths: [ '/scope' ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [ { path: '/*' } ]
        excludedPaths: [ { path: '/"_etag"/?' } ]
      }
      // No TTL: budget docs are durable. Versioning via Bicep deploy history.
    }
    options: { throughput: containerThroughput }
  }
}

// ------------- user-tier -------------
resource userTierContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-08-15' = {
  parent: database
  name: 'user-tier'
  properties: {
    resource: {
      id: 'user-tier'
      partitionKey: {
        paths: [ '/oid' ]
        kind: 'Hash'
      }
      // No TTL: tier-sync function does explicit upsert + orphan removal every 6h.
    }
    options: { throughput: containerThroughput }
  }
}

// ------------- ai-usage-monthly -------------
resource aiUsageMonthlyContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-08-15' = {
  parent: database
  name: 'ai-usage-monthly'
  properties: {
    resource: {
      id: 'ai-usage-monthly'
      partitionKey: {
        paths: [ '/oid' ]
        kind: 'Hash'
      }
      // 90-day TTL: history beyond that lives in PBIX / Event Hub capture only.
      defaultTtl: 7776000
    }
    options: { throughput: containerThroughput }
  }
}

// Outputs consumed by `apim.citadel-patch.md` Named Values.
output budgetsContainerUrl  string = '${account.properties.documentEndpoint}dbs/${databaseName}/colls/budgets'
output userTierContainerUrl string = '${account.properties.documentEndpoint}dbs/${databaseName}/colls/user-tier'
output usageContainerUrl    string = '${account.properties.documentEndpoint}dbs/${databaseName}/colls/ai-usage-monthly'
