# CLAUDE.md - Universal Gateway Implementation Guide

This document is for **Claude Code AI assistant**. It contains implementation details, code patterns, and flow information for the Universal Gateway subscription management feature.

---

## Project Overview

**Universal Consumer Management** enables developers to subscribe to APIs deployed on external gateways (AWS, Azure, Kong, Envoy) through a unified Developer Portal.

### Architecture Model

**WSO2 = Control Plane (Management)**
- Subscription lifecycle management
- Authorization enforcement (app ownership, API access)
- Credential orchestration

**Gateways = Data Plane (Runtime)**
- Runtime API traffic (bypasses WSO2)
- Local credential validation
- Rate limiting and analytics

**Key Constraint:** WSO2 does NOT see runtime traffic. No introspection, throttling enforcement, or real-time analytics.

---

## Repository Structure

```
wso2-carbon-apimgt/                    # Core APIM
├── components/apimgt/
│   ├── org.wso2.carbon.apimgt.api/    # Interfaces, models
│   │   └── FederatedSubscriptionAgent.java ← Main agent interface
│   ├── org.wso2.carbon.apimgt.impl/   # DAO, services
│   │   ├── dao/ApiMgtDAO.java         # Database access
│   │   └── federated/gateway/FederatedSubscriptionAgentFactory.java
│   └── org.wso2.carbon.apimgt.rest.api.store.v1/  # DevPortal REST API
│       ├── src/main/resources/devportal-api.yaml  # OpenAPI spec
│       └── impl/SubscriptionsApiServiceImpl.java  # Service implementation
│
wso2-apim-gw-connectors/               # Gateway connectors
├── aws/                               # AWS API Gateway
├── azure/                             # Azure APIM
│   └── AzureFederatedSubscriptionAgent.java ← Reference implementation
├── kong/                              # Kong Gateway
└── eg/                                # Envoy Gateway
```

---

## Entity Mapping Quick Reference

| WSO2 Entity | AWS | Azure | Kong | Envoy |
|-------------|-----|-------|------|-------|
| Application | *(none)* | *(none)* | *(none)* | *(labels only)* |
| API | Usage Plan | API | Route + ACL Plugin | HTTPRoute + SecurityPolicy |
| Subscription | API Key | Subscription | Consumer + key-auth | Secret |

**Key Principle:** Application-level entities skipped on all gateways. WSO2 enforces app ownership before subscription creation.

---

## Key Files & Their Roles

### Core Interfaces & Models

**FederatedSubscriptionAgent.java**
- Location: `org.wso2.carbon.apimgt.api/src/main/java/org/wso2/carbon/apimgt/api/`
- Purpose: Main interface all gateway agents implement
- Key methods:
  - `init(Environment, String organization)` - Initialize with credentials
  - `createSubscription(FederatedSubscriptionRequest)` - Create credential
  - `deleteSubscription(String externalId)` - Delete credential
  - `regenerateCredential(String externalId)` - Regenerate credential
  - `getInvocationInstruction(String referenceArtifact)` - Parse artifact
  - `getSupportedAuthTypes(String apiReferenceArtifact)` - Check subscription support
  - `retrieveCredential(String externalId)` - Retrieve full credential (optional)

**Models:**
- `FederatedCredential` - Credential metadata (type, value, timestamps)
- `FederatedSubscriptionRequest` - Subscription creation request
- `InvocationInstruction` - How to invoke the API (headers, URLs)

### Database

**Table:** `AM_SUBSCRIPTION_EXTERNAL_MAPPING`
- Location: `features/apimgt/org.wso2.carbon.apimgt.core.feature/src/main/resources/sql/`
- Schema:
  ```sql
  CREATE TABLE AM_SUBSCRIPTION_EXTERNAL_MAPPING (
      SUBSCRIPTION_UUID VARCHAR(256) NOT NULL,
      GATEWAY_ENV_ID VARCHAR(255) NOT NULL,
      EXTERNAL_SUBSCRIPTION_ID VARCHAR(512) NOT NULL,
      REFERENCE_ARTIFACT LONGBLOB,  -- Gateway-specific metadata
      CREATED_TIME TIMESTAMP,
      LAST_UPDATED_TIME TIMESTAMP,
      PRIMARY KEY (SUBSCRIPTION_UUID, GATEWAY_ENV_ID)
  );
  ```

**DAO:** `org.wso2.carbon.apimgt.impl.dao.ApiMgtDAO`
- Methods:
  - `addSubscriptionExternalMapping(...)` - Store mapping
  - `getSubscriptionExternalMapping(...)` - Retrieve mapping
  - `deleteSubscriptionExternalMapping(...)` - Remove mapping
  - `getApiExternalApiMappingReference(...)` - Get API reference artifact

### REST API

**OpenAPI Spec:** `devportal-api.yaml`
- Location: `org.wso2.carbon.apimgt.rest.api.store.v1/src/main/resources/`
- Endpoints:
  - `POST /subscriptions/{id}/federated-subscription`
  - `GET /subscriptions/{id}/federated-subscription`
  - `DELETE /subscriptions/{id}/federated-subscription`
  - `POST /subscriptions/{id}/regenerate-credential`
  - `GET /apis/{apiId}/subscription-support`

**Service Implementation:** `SubscriptionsApiServiceImpl.java` or `ApisApiServiceImpl.java`
- Location: `org.wso2.carbon.apimgt.rest.api.store.v1/src/main/java/.../impl/`

---

## Implementation Patterns

### 1. Agent Factory Pattern

**Reference:** `FederatedApplicationDiscoveryFactory.java`

```java
public class FederatedSubscriptionAgentFactory {

    // Cache agents per organization:environmentUuid
    private static final Map<String, FederatedSubscriptionAgent> agentCache =
        new ConcurrentHashMap<>();

    public static FederatedSubscriptionAgent getSubscriptionAgent(
            Environment environment, String organization) throws APIManagementException {

        String cacheKey = organization + ":" + environment.getUuid();

        // Return cached agent if available
        FederatedSubscriptionAgent cachedAgent = agentCache.get(cacheKey);
        if (cachedAgent != null) {
            return cachedAgent;
        }

        // Double-checked locking for thread safety
        synchronized (cacheKey.intern()) {
            cachedAgent = agentCache.get(cacheKey);
            if (cachedAgent != null) {
                return cachedAgent;
            }

            // Get agent configuration from ServiceReferenceHolder
            GatewayAgentConfiguration agentConfig = ServiceReferenceHolder.getInstance()
                    .getExternalGatewayConnectorConfiguration(environment.getGatewayType());

            String implClassName = agentConfig.getSubscriptionAgentImplementation();

            // Decrypt environment credentials
            APIAdminImpl apiAdmin = new APIAdminImpl();
            Environment resolvedEnv = apiAdmin.getEnvironmentWithoutPropertyMasking(
                organization, environment.getUuid());
            resolvedEnv = apiAdmin.decryptGatewayConfigurationValues(resolvedEnv);

            // Instantiate and init agent via reflection
            Class<?> clazz = Class.forName(implClassName);
            FederatedSubscriptionAgent agent =
                (FederatedSubscriptionAgent) clazz.newInstance();
            agent.init(resolvedEnv, organization);

            // Cache the agent
            agentCache.put(cacheKey, agent);
            return agent;
        }
    }

    public static void clearAgentCache(String organization, String environmentId) {
        agentCache.remove(organization + ":" + environmentId);
    }
}
```

**Key Points:**
- Agents are pooled per `organization:environmentUuid`
- Uses `ConcurrentHashMap` with double-checked locking
- Credentials decrypted via `APIAdminImpl.decryptGatewayConfigurationValues()`
- Reflection-based instantiation from `GatewayAgentConfiguration`

### 2. Credential Visibility Strategy

**Pattern:**
- **CREATE/REGENERATE:** Return full key (one-time display)
- **GET:** Return masked key (`••••••••ab12`)

**Implementation:**
```java
// On CREATE - return full key
FederatedCredential credential = new FederatedCredential();
credential.setCredentialValue(fullKeyValue);  // Full value!
credential.setMasked(false);

// On GET - return masked
String maskedValue = maskCredential(fullKeyValue);  // "••••••••ab12"
credential.setCredentialValue(maskedValue);
credential.setMasked(true);

// Masking function (8 bullets + last 4 chars)
protected String maskCredential(String credentialValue) {
    if (credentialValue == null || credentialValue.isEmpty()) {
        return credentialValue;
    }
    int length = credentialValue.length();
    int visibleChars = 4;
    if (length <= visibleChars) {
        return "•".repeat(length);
    }
    int maskLength = Math.min(8, length - visibleChars);
    return "•".repeat(maskLength) + credentialValue.substring(length - visibleChars);
}
```

### 3. Reference Artifact Pattern

**Design:** Each connector owns its reference artifact format.

**Artifact Structure (JSON in LONGBLOB):**
```json
{
  "credential": {
    "credentialType": "opaque-api-key",
    "maskedValue": "••••••••ab12",
    "isValueRetrievable": true
  },
  "invocationInstruction": {
    "gatewayType": "Azure",
    "headerName": "Ocp-Apim-Subscription-Key",
    "basePath": "/api/v1",
    "curlExample": "curl -H 'Ocp-Apim-Subscription-Key: YOUR_KEY' ...",
    "notes": "You can also pass via query param: subscription-key"
  }
}
```

**Building Artifact:**
```java
@Override
public String buildSubscriptionReferenceArtifact(
        FederatedCredential credential, InvocationInstruction instruction) {

    JsonObject json = new JsonObject();

    if (credential != null) {
        JsonObject credJson = new JsonObject();
        credJson.addProperty("credentialType", credential.getCredentialType());
        credJson.addProperty("maskedValue", maskCredential(credential.getCredentialValue()));
        credJson.addProperty("isValueRetrievable", credential.isValueRetrievable());
        json.add("credential", credJson);
    }

    if (instruction != null) {
        JsonObject instrJson = new JsonObject();
        instrJson.addProperty("gatewayType", instruction.getGatewayType());
        instrJson.addProperty("headerName", instruction.getHeaderName());
        instrJson.addProperty("basePath", instruction.getBasePath());
        instrJson.addProperty("curlExample", instruction.getCurlExample());
        instrJson.addProperty("notes", instruction.getNotes());
        json.add("invocationInstruction", instrJson);
    }

    return json.toString();
}
```

**Parsing Artifact:**
```java
@Override
public FederatedCredential extractCredentialFromReferenceArtifact(
        String subscriptionReferenceArtifact) {

    FederatedCredential credential = new FederatedCredential();
    if (subscriptionReferenceArtifact == null || subscriptionReferenceArtifact.isEmpty()) {
        return credential;
    }

    try {
        JsonObject json = JsonParser.parseString(subscriptionReferenceArtifact)
            .getAsJsonObject();
        JsonObject credJson = json.has("credential")
            ? json.getAsJsonObject("credential") : null;

        if (credJson != null) {
            if (credJson.has("credentialType")) {
                credential.setCredentialType(credJson.get("credentialType").getAsString());
            }
            if (credJson.has("maskedValue")) {
                credential.setCredentialValue(credJson.get("maskedValue").getAsString());
            }
            if (credJson.has("isValueRetrievable")) {
                credential.setValueRetrievable(
                    credJson.get("isValueRetrievable").getAsBoolean());
            }
        }
    } catch (JsonSyntaxException e) {
        log.warn("Failed to parse subscription reference artifact", e);
    }

    return credential;
}
```

### 4. Identifier Naming Convention

**Pattern:** `wso2_{subscriptionUuid}`

**Example:** `wso2_80369180-7d90-4ee8-99a1-19fa68512aa5`

**Length:** 41 characters (fits all gateway limits)

**Implementation:**
```java
private String generateExternalSubscriptionId(FederatedSubscriptionRequest request) {
    return "wso2_" + sanitize(request.getSubscriptionUuid());
}

private String sanitize(String value) {
    if (value == null || value.isEmpty()) {
        return "null";
    }
    // Replace invalid characters with underscores, keep hyphens
    return value.replaceAll("[^a-zA-Z0-9-]", "_");
}
```

**Rationale:**
- All context (org, app, API, env) stored in `AM_SUBSCRIPTION_EXTERNAL_MAPPING`
- No need to encode context in external ID
- Simpler and shorter

---

## Subscription Flow (End-to-End)

### 1. Create Subscription

**REST API Request:**
```
POST /subscriptions/{subscriptionId}/federated-subscription
```

**Flow:**
```
1. REST API receives request
2. Validate subscription exists and belongs to user
3. Get API details → Check if external gateway API
4. Get gateway environment ID from AM_API_EXTERNAL_API_MAPPING
5. Get API reference artifact from AM_API_EXTERNAL_API_MAPPING
6. Get subscription agent via FederatedSubscriptionAgentFactory
7. Build FederatedSubscriptionRequest
8. Call agent.createSubscription(request)
   ├── Agent creates credential on external gateway
   └── Returns FederatedCredential (FULL key value)
9. Get invocation instruction: agent.getInvocationInstruction(apiRefArtifact)
10. Build subscription reference artifact
11. Store in AM_SUBSCRIPTION_EXTERNAL_MAPPING
12. Return FederatedSubscriptionInfoDTO (full credential, one-time display)
```

**Service Implementation Pattern:**
```java
@Override
public Response createFederatedSubscription(String subscriptionId,
        MessageContext messageContext) throws APIManagementException {

    String organization = RestApiUtil.getValidatedOrganization(messageContext);
    String username = RestApiCommonUtil.getLoggedInUsername();

    // 1. Get subscription
    ApiMgtDAO apiMgtDAO = ApiMgtDAO.getInstance();
    SubscriptionDTO subscription = apiMgtDAO.getSubscriptionByUUID(subscriptionId);

    // 2. Validate it's a federated API
    API api = apiConsumer.getAPIbyUUID(subscription.getApiId(), organization);
    if (!APIConstants.EXTERNAL_GATEWAY_VENDOR.equalsIgnoreCase(api.getGatewayVendor())) {
        throw new APIManagementException("Not a federated API");
    }

    // 3. Get gateway environment and API reference artifact
    String gatewayEnvId = apiMgtDAO.getGatewayEnvironmentIdForExternalApi(api.getUuid());
    String apiReferenceArtifact = apiMgtDAO.getApiExternalApiMappingReference(
        api.getUuid(), gatewayEnvId);

    // 4. Get subscription agent
    Environment environment = apiMgtDAO.getEnvironment(organization, gatewayEnvId);
    FederatedSubscriptionAgent agent = FederatedSubscriptionAgentFactory
        .getSubscriptionAgent(environment, organization);

    // 5. Build subscription request
    FederatedSubscriptionRequest request = new FederatedSubscriptionRequest();
    request.setSubscriptionUuid(subscriptionId);
    request.setApplicationUuid(subscription.getApplicationId());
    request.setApiUuid(api.getUuid());
    request.setReferenceArtifact(apiReferenceArtifact);
    request.setOrganization(organization);

    // 6. Create subscription on gateway
    FederatedCredential credential = agent.createSubscription(request);

    // 7. Get invocation instruction
    InvocationInstruction instruction = agent.getInvocationInstruction(apiReferenceArtifact);

    // 8. Build and store reference artifact
    String subscriptionRefArtifact = agent.buildSubscriptionReferenceArtifact(
        credential, instruction);
    apiMgtDAO.addSubscriptionExternalMapping(
        subscriptionId, gatewayEnvId,
        credential.getExternalSubscriptionId(), subscriptionRefArtifact);

    // 9. Build DTO and return (full credential!)
    FederatedSubscriptionInfoDTO dto = new FederatedSubscriptionInfoDTO();
    dto.setGatewayEnvironmentId(gatewayEnvId);
    dto.setGatewayType(agent.getGatewayType());
    dto.setExternalSubscriptionId(credential.getExternalSubscriptionId());
    dto.setCredential(SubscriptionMappingUtil.toFederatedCredentialDTO(credential));
    dto.setInvocationInstruction(SubscriptionMappingUtil.toInvocationInstructionDTO(instruction));

    return Response.status(201).entity(dto).build();
}
```

### 2. Get Subscription (Masked Credential)

**REST API Request:**
```
GET /subscriptions/{subscriptionId}/federated-subscription
```

**Flow:**
```
1. REST API receives request
2. Validate subscription exists and belongs to user
3. Get subscription external mapping from AM_SUBSCRIPTION_EXTERNAL_MAPPING
4. Parse reference artifact → Extract masked credential
5. Return FederatedSubscriptionInfoDTO (masked credential)
```

**Key Point:** NO gateway call needed - masked credential in reference artifact.

### 3. Regenerate Credential

**REST API Request:**
```
POST /subscriptions/{subscriptionId}/regenerate-credential
```

**Flow:**
```
1. Get external subscription ID from AM_SUBSCRIPTION_EXTERNAL_MAPPING
2. Get subscription agent
3. Call agent.regenerateCredential(externalSubscriptionId)
   ├── Agent regenerates on gateway
   └── Returns NEW FederatedCredential (FULL key value)
4. Get invocation instruction (unchanged)
5. Update reference artifact in AM_SUBSCRIPTION_EXTERNAL_MAPPING
6. Return FederatedCredentialDTO (full credential, one-time display)
```

### 4. Delete Subscription

**REST API Request:**
```
DELETE /subscriptions/{subscriptionId}/federated-subscription
```

**Flow:**
```
1. Get external subscription ID from AM_SUBSCRIPTION_EXTERNAL_MAPPING
2. Get subscription agent
3. Call agent.deleteSubscription(externalSubscriptionId)
   └── Agent deletes from gateway
4. Delete from AM_SUBSCRIPTION_EXTERNAL_MAPPING
5. Return 204 No Content
```

### 5. Check Subscription Support (NEW)

**REST API Request:**
```
GET /apis/{apiId}/subscription-support
```

**Flow:**
```
1. Get API details
2. Validate it's an external gateway API
3. Get gateway environment ID
4. Get API reference artifact from AM_API_EXTERNAL_API_MAPPING
5. Get subscription agent
6. Call agent.getSupportedAuthTypes(apiReferenceArtifact)
   └── Agent queries gateway to check subscription requirement
7. Return SubscriptionSupportInfoDTO
   {
     "supportedAuthTypes": ["opaque-api-key"] or [],
     "requiresSubscription": true or false
   }
```

**Implementation Pattern:**
```java
@Override
public Response getApiSubscriptionSupport(String apiId, MessageContext messageContext)
        throws APIManagementException {

    String organization = RestApiUtil.getValidatedOrganization(messageContext);

    // 1. Get API
    API api = apiConsumer.getAPIbyUUID(apiId, organization);

    // 2. Validate external gateway API
    if (!APIConstants.EXTERNAL_GATEWAY_VENDOR.equalsIgnoreCase(api.getGatewayVendor())) {
        throw new APIManagementException("Not a federated API");
    }

    // 3. Get gateway environment and API reference artifact
    ApiMgtDAO apiMgtDAO = ApiMgtDAO.getInstance();
    String gatewayEnvId = apiMgtDAO.getGatewayEnvironmentIdForExternalApi(api.getUuid());
    String apiReferenceArtifact = apiMgtDAO.getApiExternalApiMappingReference(
        api.getUuid(), gatewayEnvId);

    // 4. Get subscription agent
    Environment environment = apiMgtDAO.getEnvironment(organization, gatewayEnvId);
    FederatedSubscriptionAgent agent = FederatedSubscriptionAgentFactory
        .getSubscriptionAgent(environment, organization);

    // 5. Check supported auth types
    String[] supportedAuthTypes = agent.getSupportedAuthTypes(apiReferenceArtifact);

    // 6. Build response
    SubscriptionSupportInfoDTO dto = new SubscriptionSupportInfoDTO();
    dto.setSupportedAuthTypes(Arrays.asList(supportedAuthTypes));
    dto.setRequiresSubscription(supportedAuthTypes.length > 0);

    return Response.ok().entity(dto).build();
}
```

---

## Azure Agent Implementation Reference

**File:** `wso2-apim-gw-connectors/azure/components/azure.gw.manager/src/main/java/org/wso2/azure/gw/client/AzureFederatedSubscriptionAgent.java`

### Key Methods

**1. Initialize:**
```java
@Override
public void init(Environment environment, String organization) throws APIManagementException {
    String tenantId = environment.getAdditionalProperties().get(AZURE_ENVIRONMENT_TENANT_ID);
    String clientId = environment.getAdditionalProperties().get(AZURE_ENVIRONMENT_CLIENT_ID);
    String clientSecret = environment.getAdditionalProperties().get(AZURE_ENVIRONMENT_CLIENT_SECRET);
    String subscriptionId = environment.getAdditionalProperties().get(AZURE_ENVIRONMENT_SUBSCRIPTION_ID);

    TokenCredential cred = new ClientSecretCredentialBuilder()
        .tenantId(tenantId)
        .clientId(clientId)
        .clientSecret(clientSecret)
        .build();

    AzureProfile profile = new AzureProfile(tenantId, subscriptionId, AzureEnvironment.AZURE);
    manager = ApiManagementManager.configure().authenticate(cred, profile);

    resourceGroup = environment.getAdditionalProperties().get(AZURE_ENVIRONMENT_RESOURCE_GROUP);
    serviceName = environment.getAdditionalProperties().get(AZURE_ENVIRONMENT_SERVICE_NAME);
    hostname = environment.getAdditionalProperties().get(AZURE_ENVIRONMENT_HOSTNAME);
}
```

**2. Create Subscription:**
```java
@Override
public FederatedCredential createSubscription(FederatedSubscriptionRequest request)
        throws APIManagementException {

    // Extract Azure API ID from reference artifact
    String azureApiId = extractAzureApiIdFromReferenceArtifact(request.getReferenceArtifact());

    // Generate subscription name
    String subscriptionName = "wso2_" + sanitize(request.getSubscriptionUuid());
    String displayName = "WSO2 Subscription - " + request.getSubscriptionUuid();

    // Build API scope
    String apiScope = buildApiScope(azureApiId);

    // Create subscription in Azure
    SubscriptionCreateParameters parameters = new SubscriptionCreateParameters()
        .withScope(apiScope)
        .withDisplayName(displayName)
        .withState(SubscriptionState.ACTIVE);

    SubscriptionContract subscription = manager.subscriptions()
        .createOrUpdate(resourceGroup, serviceName, subscriptionName, parameters);

    // Retrieve keys
    SubscriptionKeysContract keys = manager.subscriptions()
        .listSecrets(resourceGroup, serviceName, subscription.name());

    // Build credential (FULL key!)
    FederatedCredential credential = new FederatedCredential();
    credential.setCredentialType("opaque-api-key");
    credential.setExternalSubscriptionId(subscription.name());
    credential.setCredentialValue(keys.primaryKey());  // FULL value!
    credential.setValueRetrievable(true);
    credential.setMasked(false);

    return credential;
}
```

**3. Get Supported Auth Types:**
```java
@Override
public String[] getSupportedAuthTypes(String apiReferenceArtifact)
        throws APIManagementException {

    // Extract Azure API ID
    String azureApiId = extractAzureApiIdFromReferenceArtifact(apiReferenceArtifact);
    String apiName = extractApiNameFromId(azureApiId);

    // Get API from Azure
    ApiContract apiContract = manager.apis().get(resourceGroup, serviceName, apiName);

    // Check if subscription required
    Boolean subscriptionRequired = apiContract.subscriptionRequired();

    if (subscriptionRequired != null && subscriptionRequired) {
        return new String[]{"opaque-api-key"};
    } else {
        return new String[]{};  // No subscription security
    }
}
```

---

## Common Commands

```bash
# Build core module
cd /home/dasunw/development/repos/wso2-carbon-apimgt
mvn clean install -pl components/apimgt/org.wso2.carbon.apimgt.api -am -Dmaven.test.skip=true

# Build Azure connector
cd /home/dasunw/development/repos/wso2-apim-gw-connectors/azure
mvn clean install -pl components/azure.gw.manager -am -Dmaven.test.skip=true

# Generate DTOs from OpenAPI
cd /home/dasunw/development/repos/wso2-carbon-apimgt
mvn generate-sources -pl components/apimgt/org.wso2.carbon.apimgt.rest.api.store.v1

# Build REST API module
mvn clean install -pl components/apimgt/org.wso2.carbon.apimgt.rest.api.store.v1 -am -Dmaven.test.skip=true
```

---

## Error Handling Patterns

### Synchronous, Fail-Fast

**If gateway operation fails, WSO2 subscription creation fails:**
```java
try {
    FederatedCredential credential = agent.createSubscription(request);
    // Store in database
} catch (APIManagementException e) {
    // Gateway failed - do NOT create WSO2 subscription
    log.error("Failed to create subscription on gateway", e);
    throw e;  // Propagate to REST API
}
```

**No partial state allowed:**
- If gateway succeeds but DB insert fails → Delete from gateway
- If DB succeeds but gateway fails → Don't insert to DB

---

## Testing Approach

### Unit Tests
- Mock `ApiManagementManager` for Azure
- Mock `ApiMgtDAO` for database
- Test credential masking logic
- Test reference artifact parsing

### Integration Tests
- Deploy to test Azure APIM instance
- End-to-end subscription flow
- Credential regeneration
- Error scenarios (gateway failures)

### Manual Testing Checklist
- [ ] Create subscription → Full credential returned
- [ ] Get subscription → Masked credential returned
- [ ] Regenerate → New full credential returned
- [ ] Delete subscription → Removed from gateway
- [ ] Check subscription support → Correct auth types returned
- [ ] Try to subscribe to API without subscription support → Should fail gracefully

---

## Security Reminders

1. **Never log credentials** - Always mask in logs
2. **Never return full credentials on GET** - Only on CREATE/REGENERATE
3. **Validate user owns subscription** - Before any operation
4. **Use decrypted environment credentials** - Via `APIAdminImpl.decryptGatewayConfigurationValues()`
5. **HTTPS only** - All gateway communication over TLS

---

## Related Documents

- **Design Doc:** `.project/Universal Gateway.md` - High-level architecture and decisions
- **Repository Guide:** `CLAUDE.md` - Navigation and repo structure
