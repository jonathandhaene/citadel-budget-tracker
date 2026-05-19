// Azure Monitor alert rules for Citadel Budgets operational monitoring.
// Deploy after main.citadel.bicep to create alerts on Log Analytics workspace.

@description('Log Analytics workspace resource ID')
param workspaceId string

@description('Action Group resource ID for alert notifications')
param actionGroupId string

@description('APIM resource ID for metrics')
param apimResourceId string

@description('tier-sync Function App resource ID')
param tierSyncFunctionId string

@description('Alert severity levels configuration')
param severityLevels object = {
  critical: 0
  high: 1
  medium: 2
  low: 3
}

// Alert 1: Tier-sync Function failure
resource tierSyncFailureAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'citadel-tier-sync-failure'
  location: resourceGroup().location
  properties: {
    displayName: 'Citadel: Tier-sync function execution failed'
    description: 'Tier-sync function has failed to execute successfully in the last 6 hours'
    severity: severityLevels.high
    enabled: true
    evaluationFrequency: 'PT1H'
    scopes: [
      tierSyncFunctionId
    ]
    targetResourceTypes: [
      'Microsoft.Web/sites'
    ]
    windowSize: 'PT6H'
    criteria: {
      allOf: [
        {
          query: '''
            traces
            | where operation_Name == "tier-sync"
            | where severityLevel >= 3  // Error or Critical
            | summarize FailureCount = count() by bin(timestamp, 1h)
            '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
  }
}

// Alert 2: Mass user blocking (>10% of tier receiving 429)
resource massUserBlockingAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'citadel-mass-user-blocking'
  location: resourceGroup().location
  properties: {
    displayName: 'Citadel: >10% of users blocked (429 responses)'
    description: 'More than 10% of users in a tier are receiving budget exhaustion errors'
    severity: severityLevels.critical
    enabled: true
    evaluationFrequency: 'PT15M'
    scopes: [
      workspaceId
    ]
    targetResourceTypes: [
      'Microsoft.OperationalInsights/workspaces'
    ]
    windowSize: 'PT1H'
    criteria: {
      allOf: [
        {
          query: '''
            requests
            | where url contains "anthropic"
            | where resultCode == 429
            | extend userOid = tostring(customDimensions.userOid)
            | extend tier = tostring(customDimensions.tier)
            | summarize BlockedUsers = dcount(userOid) by tier
            | join kind=leftouter (
                requests
                | where url contains "anthropic"
                | extend userOid = tostring(customDimensions.userOid)
                | extend tier = tostring(customDimensions.tier)
                | summarize TotalUsers = dcount(userOid) by tier
            ) on tier
            | extend BlockedPercentage = (BlockedUsers * 100.0) / TotalUsers
            | where BlockedPercentage > 10
            '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
  }
}

// Alert 3: APIM → Cosmos latency P95 > 500ms
resource apimCosmosLatencyAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'citadel-apim-cosmos-latency'
  location: 'global'
  properties: {
    displayName: 'Citadel: APIM → Cosmos latency P95 > 500ms'
    description: 'Backend request duration to Cosmos DB exceeds 500ms at P95, indicating performance degradation'
    severity: severityLevels.medium
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [
      apimResourceId
    ]
    targetResourceType: 'Microsoft.ApiManagement/service'
    criteria: {
      allOf: [
        {
          name: 'BackendDurationP95'
          metricName: 'BackendDuration'
          metricNamespace: 'Microsoft.ApiManagement/service'
          operator: 'GreaterThan'
          threshold: 500
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'BackendUrl'
              operator: 'Include'
              values: [
                '*cosmos*'
                '*documents.azure*'
              ]
            }
          ]
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    actions: [
      {
        actionGroupId: actionGroupId
      }
    ]
  }
}

// Alert 4: Budget cache hit rate < 70%
resource budgetCacheHitRateAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'citadel-budget-cache-low-hit-rate'
  location: resourceGroup().location
  properties: {
    displayName: 'Citadel: Budget cache hit rate < 70%'
    description: 'APIM cache hit rate for budget checks is below 70%, causing excessive Cosmos queries'
    severity: severityLevels.medium
    enabled: true
    evaluationFrequency: 'PT30M'
    scopes: [
      workspaceId
    ]
    targetResourceTypes: [
      'Microsoft.OperationalInsights/workspaces'
    ]
    windowSize: 'PT1H'
    criteria: {
      allOf: [
        {
          query: '''
            traces
            | where message contains "budget-check"
            | extend cacheHit = tobool(customDimensions.cacheHit)
            | summarize Hits = countif(cacheHit == true), Misses = countif(cacheHit == false)
            | extend HitRate = (Hits * 100.0) / (Hits + Misses)
            | where HitRate < 70
            '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
  }
}

// Alert 5: Tier-sync stale data (>6h since last successful run)
resource tierSyncStaleAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'citadel-tier-sync-stale'
  location: resourceGroup().location
  properties: {
    displayName: 'Citadel: Tier-sync data stale (>6h old)'
    description: 'Tier-sync function has not completed successfully in over 6 hours'
    severity: severityLevels.high
    enabled: true
    evaluationFrequency: 'PT1H'
    scopes: [
      workspaceId
    ]
    targetResourceTypes: [
      'Microsoft.OperationalInsights/workspaces'
    ]
    windowSize: 'PT6H'
    criteria: {
      allOf: [
        {
          query: '''
            traces
            | where operation_Name == "tier-sync"
            | where message contains "complete"
            | where severityLevel <= 2  // Success or Info
            | summarize LastSuccess = max(timestamp)
            | extend HoursSinceSuccess = datetime_diff('hour', now(), LastSuccess)
            | where HoursSinceSuccess > 6
            '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
  }
}

output tierSyncFailureAlertId string = tierSyncFailureAlert.id
output massUserBlockingAlertId string = massUserBlockingAlert.id
output apimCosmosLatencyAlertId string = apimCosmosLatencyAlert.id
output budgetCacheHitRateAlertId string = budgetCacheHitRateAlert.id
output tierSyncStaleAlertId string = tierSyncStaleAlert.id
