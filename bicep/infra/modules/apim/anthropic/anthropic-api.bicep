// Bicep module: register the Citadel Anthropic API into an existing APIM instance.
// Paper-only — placeholders are intentional. The full file is illustrative; production wiring
// happens via `bicep/infra/main.citadel.bicep`.

@description('APIM service name (existing).')
param apimName string

@description('API path suffix mounted on the APIM gateway (e.g. "anthropic" -> /anthropic/v1/messages).')
param apiPath string = 'anthropic'

@description('Backend URL of the Foundry Anthropic deployment.')
param foundryAnthropicEndpoint string

@description('Foundry deployment name (e.g. "claude-sonnet-4"). Reported in usage telemetry; not part of the URL path.')
param claudeDeploymentName string

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

// Backend pointing at Foundry. APIM managed identity is used for auth (see API policy).
resource anthropicBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'citadel-anthropic-backend'
  properties: {
    protocol: 'http'
    url: foundryAnthropicEndpoint
    description: 'Foundry Anthropic backend (Citadel). Auth via APIM-MI in API policy.'
  }
}

// API definition — OpenAPI spec lives next to this file.
resource anthropicApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'citadel-anthropic-api'
  properties: {
    displayName: 'Citadel Anthropic API'
    path: apiPath
    protocols: [ 'https' ]
    subscriptionRequired: false  // D1: Entra JWT is the credential, no APIM subscription key.
    format: 'openapi'
    value: loadTextContent('./anthropic-api-spec.yaml')
    serviceUrl: foundryAnthropicEndpoint
  }
}

// API-level policy: includes auth + budget-check + usage emit fragments.
resource anthropicApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: anthropicApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../policies/anthropic-api-policy.xml')
  }
}

output anthropicApiPath string = apiPath
output anthropicBackendId string = anthropicBackend.id
