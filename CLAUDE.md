# CLAUDE.md - Universal Gateway Consumer Strategy

## Project Context

This project implements **Universal Consumer Management** for WSO2 API Manager's Gateway Federation feature. It enables developers to subscribe to APIs deployed on external gateways (AWS, Azure, Kong, Envoy) through a unified Developer Portal experience.

### Project Evolution
- **Previous approach (Discarded):** "Application Federation" - focused on discovering/importing existing external subscriptions into WSO2
- **Current approach:** "Universal Control Plane" - WSO2 orchestrates subscription creation on external gateways, providing a unified developer experience

### What "Universal Control Plane" Means

**WSO2 = Control Plane (Subscription Management)**
- Developer creates subscriptions in WSO2 DevPortal
- WSO2 enforces authorization (app ownership, API access)
- WSO2 orchestrates credential creation on gateways
- WSO2 displays credentials to developers

**Gateways = Data Plane (Runtime Validation)**
- Runtime API calls go **directly to gateways** (bypass WSO2)
- Gateways validate credentials locally
- Gateways enforce their own rate limits
- **WSO2 does NOT see runtime traffic**

### Key Principles
1. **Universal Developer Portal** - No vendor-specific concepts visible to developers
2. **WSO2 as Subscription Orchestrator** - Manages lifecycle, gateways handle runtime
3. **Simplified Entity Model** - Skip Application-level entities (WSO2 enforces app ownership at subscription time)
4. **Opaque API Keys** - The lowest common denominator across all gateways
5. **Flexible Credential Sourcing** - Gateway generates key, WSO2 retrieves and displays
6. **Per-API-Subscription Credentials** - Each subscription gets its own unique credential
7. **Connector-Owned Parsing** - Each connector parses its own reference artifact format

---

## Architecture: Control Plane vs Data Plane

### Subscription Flow (WSO2 Control Plane)
```
Developer → WSO2 DevPortal → Subscribe
  ↓
WSO2 validates (app ownership, API access)
  ↓
WSO2 → Gateway Agent → Create credential
  ↓
Gateway returns credential → WSO2 stores + displays
```

### Runtime Flow (Gateway Data Plane)
```
Developer → curl -H "apikey: abc" https://gateway/api
  ↓
DIRECT to gateway (bypasses WSO2!)
  ↓
Gateway validates credential → Forward to backend
```

**WSO2 does NOT see runtime API traffic. No introspection, throttling enforcement, or analytics at runtime.**

---

## Repository Structure

```
wso2-carbon-apimgt/                    # Core APIM components
├── components/apimgt/
│   ├── org.wso2.carbon.apimgt.api/    # Interfaces and models
│   ├── org.wso2.carbon.apimgt.impl/   # DAO, service implementations
│   └── org.wso2.carbon.apimgt.rest.api.store.v1/  # DevPortal REST API
│
wso2-apim-gw-connectors/               # Gateway connectors
├── aws/                               # AWS API Gateway connector
├── azure/                             # Azure APIM connector
├── kong/                              # Kong Gateway connector (REFERENCE)
└── eg/                                # Envoy Gateway connector
```

---

## Key Files & Locations

### Interfaces (to create/modify)
- `org.wso2.carbon.apimgt.api.FederatedSubscriptionAgent` - **NEW** - Main agent interface
- `org.wso2.carbon.apimgt.api.model.GatewayAgentConfiguration` - Add `getSubscriptionAgentImplementation()`

### Models (to create)
- `org.wso2.carbon.apimgt.api.model.FederatedSubscription` - Subscription with gateway context
- `org.wso2.carbon.apimgt.api.model.FederatedCredential` - Credential metadata
- `org.wso2.carbon.apimgt.api.model.InvocationInstruction` - How to call the API

### Database
- Table: `AM_SUBSCRIPTION_EXTERNAL_MAPPING` - Links WSO2 subscription to gateway entities
  - Key columns: `SUBSCRIPTION_UUID`, `GATEWAY_ENV_ID`, `EXTERNAL_SUBSCRIPTION_ID`, `REFERENCE_ARTIFACT` (LONGBLOB for gateway-specific metadata)
- Location: `features/apimgt/org.wso2.carbon.apimgt.core.feature/src/main/resources/sql/`
- DAO: `org.wso2.carbon.apimgt.impl.dao.ApiMgtDAO`
- Constants: `org.wso2.carbon.apimgt.impl.dao.constants.SQLConstants`

### REST API (DevPortal)
- OpenAPI: `org.wso2.carbon.apimgt.rest.api.store.v1/src/main/resources/devportal-api.yaml`
- DTOs: `org.wso2.carbon.apimgt.rest.api.store.v1.dto.*`
- Services: `org.wso2.carbon.apimgt.rest.api.store.v1.impl.*`

### Reference Implementation
- **Kong Connector** - Already implements the subscription pattern
  - `kong/gateway-connector/internal/events/subscription_handler.go`
  - `kong/gateway-connector/pkg/transformer/transformer.go`
  - `kong/gateway-connector/pkg/synchronizer/subscriptions_fetcher.go`

---

## Entity Mapping Quick Reference (Simplified)

| WSO2 Entity | AWS | Azure | Kong | Envoy |
|-------------|-----|-------|------|-------|
| Organization | Tag prefix | APIM Service | Namespace | Namespace |
| Application | *(none)* | *(none)* | *(none)* | *(labels only)* |
| API | Usage Plan | API | Route + ACL Plugin | HTTPRoute + SecurityPolicy |
| Subscription | API Key | Subscription (API-scoped) | **Consumer + key-auth** | Secret |

**Rationale:** Application-level entities skipped on all gateways. WSO2 enforces app ownership before subscription creation. Each subscription creates exactly one gateway entity for simpler lifecycle management.

---

## Implementation Checklist

### Phase 1: Core Abstractions
- [x] Create `FederatedSubscriptionAgent` interface
- [x] Create `FederatedSubscriptionAgentFactory` class
- [x] Create models: `FederatedCredential`, `InvocationInstruction`
- [x] Create `AM_SUBSCRIPTION_EXTERNAL_MAPPING` table (all DB dialects)
- [x] Add DAO methods to `ApiMgtDAO.java`
- [x] Add SQL constants to `SQLConstants.java`

### Phase 2: DTOs & REST API
- [x] Create `FederatedSubscriptionInfoDTO`
- [x] Create `FederatedCredentialDTO`
- [x] Create `InvocationInstructionDTO`
- [x] Update `devportal-api.yaml` OpenAPI spec
- [x] Add `POST /subscriptions/{id}/federated-subscription` endpoint (create)
- [x] Add `GET /subscriptions/{id}/federated-subscription` endpoint (get)
- [x] Add `DELETE /subscriptions/{id}/federated-subscription` endpoint (delete)
- [x] Add `POST /subscriptions/{id}/regenerate-credential` endpoint

### Phase 3: Gateway Agents
- [ ] **Envoy Agent** (POC target - wire existing code)
  - [ ] Create `EnvoyFederatedSubscriptionAgent`
  - [ ] Wire to existing `DeploySecretCR`, `DeploySecurityPolicyCR`
- [x] **Azure Agent** (Medium effort)
  - [x] Create `AzureFederatedSubscriptionAgent`
  - [x] Implement Subscription CRUD, credential regeneration, invocation instructions
- [ ] **AWS Agent** (High effort)
  - [ ] Create `AWSFederatedSubscriptionAgent`
  - [ ] Implement Usage Plan, API Key CRUD

---

## Coding Patterns

### Agent Factory Pattern
```java
// Follow existing FederatedApplicationDiscoveryFactory pattern
// Reference: org.wso2.carbon.apimgt.impl.federated.gateway.FederatedApplicationDiscoveryFactory

public class FederatedSubscriptionAgentFactory {

    // Cache for agents per organization and environment
    private static final Map<String, FederatedSubscriptionAgent> agentCache = new ConcurrentHashMap<>();

    public static FederatedSubscriptionAgent getSubscriptionAgent(Environment environment, String organization)
            throws APIManagementException {

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

            // Get agent configuration
            GatewayAgentConfiguration agentConfig = ServiceReferenceHolder.getInstance()
                    .getExternalGatewayConnectorConfiguration(environment.getGatewayType());

            String implClassName = agentConfig.getSubscriptionAgentImplementation();

            // Decrypt environment credentials
            APIAdminImpl apiAdmin = new APIAdminImpl();
            Environment resolvedEnv = apiAdmin.getEnvironmentWithoutPropertyMasking(organization, environment.getUuid());
            resolvedEnv = apiAdmin.decryptGatewayConfigurationValues(resolvedEnv);

            // Instantiate and init agent
            Class<?> clazz = Class.forName(implClassName);
            FederatedSubscriptionAgent agent = (FederatedSubscriptionAgent) clazz.newInstance();
            agent.init(resolvedEnv, organization);

            agentCache.put(cacheKey, agent);
            return agent;
        }
    }

    public static void clearAgentCache(String organization, String environmentId) {
        agentCache.remove(organization + ":" + environmentId);
    }
}
```

### Credential Visibility
- **CREATE**: Return full key (one-time display)
- **GET**: Return masked key (`••••••••ab12`)
- **REGENERATE**: Return new full key (one-time display)

### Identifier Naming
Pattern: `wso2_{subscriptionUuid}` (41 chars, fits all gateway limits)
All context (org, app, API, env) is in `AM_SUBSCRIPTION_EXTERNAL_MAPPING`.

---

## Common Commands

```bash
# Build core module
mvn clean install -pl components/apimgt/org.wso2.carbon.apimgt.api -am

# Build REST API module
mvn clean install -pl components/apimgt/org.wso2.carbon.apimgt.rest.api.store.v1 -am

# Run unit tests
mvn test -pl components/apimgt/org.wso2.carbon.apimgt.impl

# Generate DTOs from OpenAPI
mvn generate-sources -pl components/apimgt/org.wso2.carbon.apimgt.rest.api.store.v1
```

---

## Resolved Decisions

### 1. Credential Storage Strategy ✅ DECIDED
- **Decision:** Masked secrets only, user can regenerate if forgotten
- **Rationale:** Simpler implementation, no encrypted storage complexity
- **UX:** Full key shown once at creation/regeneration, then masked forever

### 2. Application-Level Entities ✅ DECIDED
- **Decision:** Skip Application-level entities on ALL gateways (Azure, AWS, Kong, Envoy)
- **Rationale:** WSO2 already enforces app ownership before subscription creation. Gateways are credential providers only.
- **Implementation:**
  - Azure: No User creation (Subscriptions are standalone)
  - AWS: No container (API Keys attach to Usage Plans)
  - Kong: Consumer = Subscription (not Consumer = Application)
  - Envoy: No consumer concept (just labels)

### 3. Reference Artifact Parsing ✅ DECIDED
- **Decision:** Connectors parse their own reference artifact format (not REST API layer)
- **Rationale:** Separation of concerns - REST API passes raw artifact, connector knows its format
- **Implementation:** `FederatedSubscriptionAgent.getInvocationInstruction(String referenceArtifact)`

### 4. Kong Consumer Strategy ✅ DECIDED
- **Decision:** Consumer created per-Subscription (not per-Application)
- **Rationale:** Simpler lifecycle (delete Consumer = cascade cleanup), consistent with other gateways
- **Implementation:** Consumer name = `wso2_{subscriptionUuid}`

### 5. Agent Lifecycle ✅ DECIDED
- **Decision:** Pooled/cached instances (like `FederatedApplicationDiscoveryFactory`)
- **Pattern:** `ConcurrentHashMap` cache with key `organization:environmentUuid`
- **Reference:** `FederatedApplicationDiscoveryFactory.java`

### 6. Error Handling ✅ DECIDED
- **Decision:** Synchronous, fail-fast
- **Behavior:** If gateway credential creation fails, no WSO2 subscription created
- **Rationale:** Operations must be synchronous for consistent state

### 7. Runtime Architecture ✅ DECIDED
- **Decision:** WSO2 = Control Plane (management), Gateways = Data Plane (runtime)
- **Implications:**
  - ❌ WSO2 does NOT see runtime API traffic
  - ❌ WSO2 cannot enforce throttling at runtime
  - ❌ WSO2 cannot provide real-time analytics
  - ✅ WSO2 manages subscription lifecycle
  - ✅ Gateways validate credentials at runtime

### 8. State Synchronization - DEFERRED
- **Q:** What if gateway credential is deleted directly on gateway side?
- **Decision:** Out of scope for v1. Future reconciliation job.

### 9. Quota/Throttling Mapping - DEFERRED
- **Q:** How is WSO2 throttling policy mapped to gateway-specific limits?
- **Decision:** Use gateway defaults for v1. Policy mapping in v2.

---

## FederatedSubscriptionAgent Interface (Draft)

```java
public interface FederatedSubscriptionAgent {

    /**
     * Initialize agent with decrypted environment credentials.
     */
    void init(Environment env, String organization);

    /**
     * Create subscription on external gateway.
     * @return Credential with full key value (one-time display)
     */
    FederatedCredential createSubscription(FederatedSubscriptionRequest request)
        throws APIManagementException;

    /**
     * Delete subscription from external gateway.
     */
    void deleteSubscription(String externalSubscriptionId)
        throws APIManagementException;

    /**
     * Regenerate credential (delete old + create new).
     * @return New credential with full key value (one-time display)
     */
    FederatedCredential regenerateCredential(String externalSubscriptionId)
        throws APIManagementException;

    /**
     * Get invocation instructions for an API.
     */
    InvocationInstruction getInvocationInstruction(String externalApiId);

    /**
     * Check if subscription exists on gateway.
     */
    boolean subscriptionExists(String externalSubscriptionId);

    /**
     * Get gateway type identifier.
     */
    String getGatewayType();
}
```

---

## Gateway SDK References

| Gateway | Java SDK | Key Classes |
|---------|----------|-------------|
| AWS | `software.amazon.awssdk:apigateway` | `ApiGatewayClient`, `CreateApiKeyRequest` |
| Azure | `com.azure.resourcemanager:azure-resourcemanager-apimanagement` | `ApiManagementManager`, `SubscriptionContract` |
| Kong | Kubernetes CRDs | `KongConsumer`, `Secret` |
| Envoy | Kubernetes CRDs | `SecurityPolicy`, `Secret` |

---

## Security Considerations

1. **Never log credentials** - Use masked values in all logs
2. **Encrypt at rest** - Use DB encryption for credential storage
3. **HTTPS only** - All credential transmission over TLS
4. **One-time display** - Full credential shown only at creation/regeneration
5. **Audit trail** - Log who accessed/regenerated credentials (without values)

---

## Testing Strategy

### Unit Tests
- Mock gateway SDKs/clients
- Test credential masking logic
- Test DAO operations

### Integration Tests
- Deploy to test gateways (dev instances)
- End-to-end subscription flow
- Credential regeneration

### Manual Testing
- DevPortal UI flow
- Copy/paste credential functionality
- Error scenarios

---

## Document References

- **Design Doc:** `.project/Unversal Gateway.md`
- **Legacy Doc (Archived):** `.project/Application Federation.md`
- **Kong Reference:** `wso2-apim-gw-connectors/kong/gateway-connector/`
