# Citadel Budgets Security Hardening Guide

This guide implements the security recommendations from the Enterprise Architecture review.

## Table of Contents
1. [RBAC Role Assignments](#rbac-role-assignments)
2. [Managed Identity Authentication](#managed-identity-authentication)
3. [Cosmos DB Firewall Rules](#cosmos-db-firewall-rules)
4. [JWT Validation Hardening](#jwt-validation-hardening)
5. [PII Data Classification](#pii-data-classification)
6. [Audit Logging](#audit-logging)

---

## 1. RBAC Role Assignments

### APIM Managed Identity → Cosmos DB

**Grant Cosmos DB Built-in Data Contributor role to APIM:**

```bash
# Get APIM managed identity principal ID
APIM_PRINCIPAL_ID=$(az apim show \
  --resource-group <resource-group> \
  --name <apim-name> \
  --query identity.principalId \
  --output tsv)

# Get Cosmos account resource ID
COSMOS_ID=$(az cosmosdb show \
  --resource-group <resource-group> \
  --name <cosmos-account-name> \
  --query id \
  --output tsv)

# Assign Cosmos DB Built-in Data Contributor role
az cosmosdb sql role assignment create \
  --account-name <cosmos-account-name> \
  --resource-group <resource-group> \
  --scope "$COSMOS_ID/dbs/ai-usage-db" \
  --principal-id $APIM_PRINCIPAL_ID \
  --role-definition-id 00000000-0000-0000-0000-000000000002
```

**In Bicep (recommended):**

```bicep
// In main.citadel.bicep or a dedicated rbac.bicep module
resource apimCosmosRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-08-15' = {
  name: guid(apim.id, cosmosAccount.id, 'cosmos-data-contributor')
  parent: cosmosAccount
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    principalId: apim.identity.principalId
    scope: '${cosmosAccount.id}/dbs/${cosmosDatabase.name}'
  }
}
```

### tier-sync Function Managed Identity → Microsoft Graph

**Grant Graph permissions to tier-sync Function:**

```bash
# Get Function managed identity principal ID
FUNCTION_PRINCIPAL_ID=$(az functionapp identity show \
  --resource-group <resource-group> \
  --name <function-app-name> \
  --query principalId \
  --output tsv)

# Get Microsoft Graph app ID (constant)
GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"

# Get Graph permission IDs
GROUP_READ_ALL="5b567255-7703-4780-807c-7be8301ae99b"  # Group.Read.All
DIRECTORY_READ_ALL="7ab1d382-f21e-4acd-a863-ba3e13f7da61"  # Directory.Read.All

# Grant permissions (requires Global Administrator or Privileged Role Administrator)
az rest --method POST \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$FUNCTION_PRINCIPAL_ID/appRoleAssignments" \
  --body "{
    \"principalId\": \"$FUNCTION_PRINCIPAL_ID\",
    \"resourceId\": \"$GRAPH_APP_ID\",
    \"appRoleId\": \"$GROUP_READ_ALL\"
  }"

az rest --method POST \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$FUNCTION_PRINCIPAL_ID/appRoleAssignments" \
  --body "{
    \"principalId\": \"$FUNCTION_PRINCIPAL_ID\",
    \"resourceId\": \"$GRAPH_APP_ID\",
    \"appRoleId\": \"$DIRECTORY_READ_ALL\"
  }"
```

**In Bicep:**
```bicep
// This requires Microsoft.Graph provider (preview)
// For now, grant permissions via post-deployment script
resource graphPermissions 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'grant-graph-permissions'
  location: location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.50.0'
    timeout: 'PT10M'
    scriptContent: '''
      # Grant Graph permissions to tier-sync Function
      az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${functionPrincipalId}/appRoleAssignments" --body '{"principalId":"${functionPrincipalId}","resourceId":"${graphAppId}","appRoleId":"5b567255-7703-4780-807c-7be8301ae99b"}'
    '''
    environmentVariables: [
      {
        name: 'functionPrincipalId'
        value: tierSyncFunction.identity.principalId
      }
    ]
    retentionInterval: 'PT1H'
  }
}
```

---

## 2. Managed Identity Authentication

### APIM → Cosmos DB (Replace Connection String)

**Update `frag-citadel-budget-check.xml` to use MI:**

```xml
<!-- OLD (connection string - INSECURE): -->
<send-request mode="new" response-variable-name="budgetDoc">
    <set-url>@{
        var namedValue = context.Variables.GetValueOrDefault("cosmos-connection-string", "");
        return $"https://{accountName}.documents.azure.com/dbs/ai-usage-db/colls/budgets/docs/{docId}";
    }</set-url>
    <set-header name="Authorization" exists-action="override">
        <value>@(context.Variables["cosmos-auth-header"])</value>
    </set-header>
</send-request>

<!-- NEW (managed identity - SECURE): -->
<send-request mode="new" response-variable-name="budgetDoc">
    <set-url>@{
        var accountName = "{{cosmos-account-name}}";
        var docId = $"tier:{tier}:model:{model}";
        return $"https://{accountName}.documents.azure.com/dbs/ai-usage-db/colls/budgets/docs/{docId}";
    }</set-url>
    <set-method>GET</set-method>
    <set-header name="x-ms-documentdb-partitionkey" exists-action="override">
        <value>@($"[\"{tier}\"]")</value>
    </set-header>
    <!-- Authenticate using APIM managed identity -->
    <authentication-managed-identity resource="https://cosmos.azure.com" />
</send-request>
```

**Remove Cosmos connection string Named Value:**
```bash
az apim nv delete \
  --resource-group <resource-group> \
  --service-name <apim-name> \
  --named-value-id cosmos-connection-string
```

### APIM → Foundry Backend

**Update `anthropic-api-policy.xml` backend auth:**

```xml
<backend>
    <set-backend-service base-url="{{foundry-anthropic-endpoint}}" />

    <!-- Strip user JWT before forwarding -->
    <set-header name="Authorization" exists-action="delete" />

    <!-- Authenticate to Foundry using APIM managed identity -->
    <authentication-managed-identity resource="https://cognitiveservices.azure.com" />
</backend>
```

---

## 3. Cosmos DB Firewall Rules

**Restrict Cosmos to APIM and tier-sync Function subnets only:**

```bash
# Get APIM outbound IP addresses
APIM_IPS=$(az apim show \
  --resource-group <resource-group> \
  --name <apim-name> \
  --query properties.publicIPAddresses \
  --output tsv)

# Get tier-sync Function outbound IPs
FUNCTION_IPS=$(az functionapp show \
  --resource-group <resource-group> \
  --name <function-app-name> \
  --query possibleOutboundIPAddresses \
  --output tsv | tr ',' '\n')

# Enable Cosmos firewall and allow only APIM + Function IPs
az cosmosdb update \
  --resource-group <resource-group> \
  --name <cosmos-account-name> \
  --enable-public-network true \
  --ip-range-filter "$APIM_IPS,$FUNCTION_IPS"

# Also allow Azure Portal access (optional, for admin)
az cosmosdb update \
  --resource-group <resource-group> \
  --name <cosmos-account-name> \
  --enable-public-network true \
  --ip-range-filter "$APIM_IPS,$FUNCTION_IPS,104.42.195.92,40.76.54.131,52.176.6.30,52.169.50.45,52.187.184.26"
```

**In Bicep:**
```bicep
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-08-15' = {
  name: cosmosAccountName
  location: location
  properties: {
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    publicNetworkAccess: 'Enabled'
    ipRules: [
      // APIM outbound IPs
      { ipAddressOrRange: apimOutboundIP1 }
      { ipAddressOrRange: apimOutboundIP2 }
      // tier-sync Function outbound IPs
      { ipAddressOrRange: functionOutboundIP1 }
      { ipAddressOrRange: functionOutboundIP2 }
      // Azure Portal (optional)
      { ipAddressOrRange: '104.42.195.92' }
      { ipAddressOrRange: '40.76.54.131' }
    ]
    // Alternative: use virtual network rules if APIM and Function are in VNets
    virtualNetworkRules: enableVNetIntegration ? [
      { id: apimSubnetId }
      { id: functionSubnetId }
    ] : []
  }
}
```

---

## 4. JWT Validation Hardening

### Add JWT Replay Protection

**Update `frag-citadel-anthropic-auth.xml` to check `iat` freshness:**

```xml
<!-- After validate-jwt, add iat freshness check -->
<validate-jwt ... output-token-variable-name="citadel-jwt">
    <!-- existing validation -->
</validate-jwt>

<!-- Check iat (issued-at) is within last 5 minutes -->
<set-variable name="jwtIat" value="@{
    var jwt = (Jwt)context.Variables["citadel-jwt"];
    var iatClaim = jwt.Claims.GetValueOrDefault("iat", "0");
    return long.Parse(iatClaim);
}" />

<set-variable name="currentTimestamp" value="@(DateTimeOffset.UtcNow.ToUnixTimeSeconds())" />

<choose>
    <when condition="@(
        long.Parse((string)context.Variables["currentTimestamp"]) -
        long.Parse((string)context.Variables["jwtIat"]) > 300
    )">
        <return-response>
            <set-status code="401" reason="Unauthorized: JWT is too old (issued > 5 minutes ago)" />
            <set-body>@{
                return new JObject(
                    new JProperty("error", "jwt_replay_suspected"),
                    new JProperty("message", "Token was issued more than 5 minutes ago")
                ).ToString();
            }</set-body>
        </return-response>
    </when>
</choose>
```

### Validate `nbf` (Not Before)

```xml
<set-variable name="jwtNbf" value="@{
    var jwt = (Jwt)context.Variables["citadel-jwt"];
    var nbfClaim = jwt.Claims.GetValueOrDefault("nbf", "0");
    return long.Parse(nbfClaim);
}" />

<choose>
    <when condition="@(
        long.Parse((string)context.Variables["jwtNbf"]) >
        long.Parse((string)context.Variables["currentTimestamp"])
    )">
        <return-response>
            <set-status code="401" reason="Unauthorized: JWT not yet valid (nbf check failed)" />
        </return-response>
    </when>
</choose>
```

---

## 5. PII Data Classification

### Tag PII Fields in Cosmos Documents

**Add Microsoft Purview classification labels:**

```json
// In budgets, user-tier, ai-usage-monthly documents:
{
  "id": "user-123",
  "oid": "00000000-0000-0000-0000-000000000000",
  "userUpn": "user@contoso.com",

  // Add PII classification metadata
  "_pii_classification": {
    "userUpn": {
      "label": "Confidential.Personal",
      "sensitivity": "PII",
      "gdprArticle": "Article 9",
      "retentionPolicy": "90-days"
    },
    "oid": {
      "label": "Confidential.Internal",
      "sensitivity": "Pseudonymous",
      "retentionPolicy": "indefinite"
    }
  }
}
```

### Enable Microsoft Purview Integration

```bash
# Enable Purview scanning on Cosmos account
az purview account create \
  --resource-group <resource-group> \
  --name <purview-account-name> \
  --location <location>

# Register Cosmos as a data source
az purview scanning data-source create \
  --name cosmos-citadel-budgets \
  --kind AzureCosmosDb \
  --collection-reference-name <collection-name> \
  --account-uri "https://<cosmos-account>.documents.azure.com"

# Run classification scan
az purview scanning trigger run-scan \
  --data-source-name cosmos-citadel-budgets \
  --scan-name pii-classification-scan
```

---

## 6. Audit Logging

### Enable Cosmos DB Diagnostic Settings

```bash
# Create Log Analytics workspace if not exists
az monitor log-analytics workspace create \
  --resource-group <resource-group> \
  --workspace-name citadel-budgets-logs

# Get workspace ID
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group <resource-group> \
  --workspace-name citadel-budgets-logs \
  --query id \
  --output tsv)

# Enable Cosmos diagnostic settings
az monitor diagnostic-settings create \
  --resource <cosmos-resource-id> \
  --name cosmos-audit-logs \
  --workspace $WORKSPACE_ID \
  --logs '[
    {"category": "DataPlaneRequests", "enabled": true},
    {"category": "MongoRequests", "enabled": false},
    {"category": "QueryRuntimeStatistics", "enabled": true},
    {"category": "PartitionKeyStatistics", "enabled": true}
  ]' \
  --metrics '[
    {"category": "Requests", "enabled": true}
  ]'
```

### Alert on Direct Data-Plane Writes

**Create alert for writes not from APIM or tier-sync:**

```kusto
// Log Analytics query
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.DOCUMENTDB"
| where Category == "DataPlaneRequests"
| where OperationName in ("Create", "Replace", "Upsert", "Delete")
| extend SourceIP = tostring(callerIpAddress_s)
| where SourceIP !in ('<apim-ip>', '<function-ip>')
| project
    TimeGenerated,
    OperationName,
    SourceIP,
    DatabaseName = databaseName_s,
    CollectionName = collectionName_s,
    DocumentId = documentId_s,
    UserAgent = userAgent_s
```

### Enable APIM Request Logging with Correlation IDs

**In `anthropic-api-policy.xml` inbound:**

```xml
<inbound>
    <!-- Generate correlation ID -->
    <set-variable name="citadel-trace-id" value="@(Guid.NewGuid().ToString())" />
    <set-header name="x-citadel-trace-id" exists-action="override">
        <value>@((string)context.Variables["citadel-trace-id"])</value>
    </set-header>

    <!-- Log request with trace ID -->
    <log-to-eventhub logger-id="citadel-event-hub">
        @{
            return new JObject(
                new JProperty("traceId", context.Variables["citadel-trace-id"]),
                new JProperty("timestamp", DateTime.UtcNow),
                new JProperty("operation", "request-start"),
                new JProperty("userOid", context.Variables.GetValueOrDefault("userOid", "")),
                new JProperty("tier", context.Variables.GetValueOrDefault("tier", "")),
                new JProperty("model", context.Request.MatchedParameters["model"])
            ).ToString();
        }
    </log-to-eventhub>
</inbound>
```

---

## Security Checklist

Before deploying to production, verify:

- [ ] APIM managed identity has Cosmos Data Contributor role (scoped to database, not account)
- [ ] tier-sync Function managed identity has Graph `Group.Read.All` + `Directory.Read.All`
- [ ] Cosmos connection strings removed from APIM Named Values
- [ ] APIM uses MI auth for all Cosmos requests (`authentication-managed-identity`)
- [ ] User JWT is stripped before forwarding to Foundry
- [ ] Cosmos firewall restricts access to APIM + Function IPs only
- [ ] JWT validation includes `iat` freshness check (< 5 minutes)
- [ ] PII fields tagged with classification labels
- [ ] Cosmos diagnostic settings enabled, streaming to Log Analytics
- [ ] Alert created for unauthorized Cosmos writes
- [ ] Correlation ID (`x-citadel-trace-id`) injected in all requests
- [ ] All secrets stored in Key Vault (if any remain)
- [ ] Private endpoints enabled for Cosmos (production)
- [ ] Microsoft Defender for Cloud enabled on all resources

---

## References

- [Azure Cosmos DB RBAC](https://learn.microsoft.com/en-us/azure/cosmos-db/how-to-setup-rbac)
- [APIM Managed Identity](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-use-managed-service-identity)
- [Microsoft Graph Permissions](https://learn.microsoft.com/en-us/graph/permissions-reference)
- [APIM Policy: authentication-managed-identity](https://learn.microsoft.com/en-us/azure/api-management/authentication-managed-identity-policy)
- [Cosmos DB Firewall](https://learn.microsoft.com/en-us/azure/cosmos-db/how-to-configure-firewall)
- [Microsoft Purview Data Classification](https://learn.microsoft.com/en-us/azure/purview/concept-best-practices-classification)
