# Implementation Plan: Universal Gateway Consumer Strategy - Core Abstraction Layer

## Overview

Implement `FederatedSubscriptionAgent` system for unified subscription management across external gateways (AWS, Azure, Kong, Envoy). Follows established patterns from `FederatedApplicationDiscovery`.

## Files to Create/Modify

### Phase 1: Core Interface and Models (API Module)

| Order | File | Type | Description |
|-------|------|------|-------------|
| 1 | `wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.api/src/main/java/org/wso2/carbon/apimgt/api/FederatedSubscriptionAgent.java` | NEW | Main agent interface |
| 2 | `wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.api/src/main/java/org/wso2/carbon/apimgt/api/model/FederatedSubscriptionRequest.java` | NEW | Input model for createSubscription |
| 3 | `wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.api/src/main/java/org/wso2/carbon/apimgt/api/model/FederatedCredential.java` | NEW | Credential output model |
| 4 | `wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.api/src/main/java/org/wso2/carbon/apimgt/api/model/InvocationInstruction.java` | NEW | API invocation instructions |
| 5 | `wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.api/src/main/java/org/wso2/carbon/apimgt/api/model/SubscriptionExternalMapping.java` | NEW | DB mapping model |
| 6 | `wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.api/src/main/java/org/wso2/carbon/apimgt/api/model/GatewayAgentConfiguration.java` | MODIFY | Add `getSubscriptionAgentImplementation()` |

### Phase 2: Factory (IMPL Module)

| Order | File | Type | Description |
|-------|------|------|-------------|
| 7 | `wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.impl/src/main/java/org/wso2/carbon/apimgt/impl/federated/gateway/FederatedSubscriptionAgentFactory.java` | NEW | Cached factory with double-checked locking |

### Phase 3: Database Layer

| Order | File | Type | Description |
|-------|------|------|-------------|
| 8 | `wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.impl/src/main/java/org/wso2/carbon/apimgt/impl/dao/constants/SQLConstants.java` | MODIFY | Add subscription mapping SQL constants |
| 9 | `wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.impl/src/main/java/org/wso2/carbon/apimgt/impl/dao/ApiMgtDAO.java` | MODIFY | Add DAO methods |

### Phase 4: SQL Schema (All Dialects)

| Order | File | Type |
|-------|------|------|
| 10 | `wso2-carbon-apimgt/features/apimgt/org.wso2.carbon.apimgt.core.feature/src/main/resources/sql/h2.sql` | MODIFY |
| 11 | `wso2-carbon-apimgt/features/apimgt/org.wso2.carbon.apimgt.core.feature/src/main/resources/sql/mysql.sql` | MODIFY |
| 12 | `wso2-carbon-apimgt/features/apimgt/org.wso2.carbon.apimgt.core.feature/src/main/resources/sql/postgresql.sql` | MODIFY |
| 13 | `wso2-carbon-apimgt/features/apimgt/org.wso2.carbon.apimgt.core.feature/src/main/resources/sql/oracle.sql` | MODIFY |
| 14 | `wso2-carbon-apimgt/features/apimgt/org.wso2.carbon.apimgt.core.feature/src/main/resources/sql/mssql.sql` | MODIFY |

---

## Interface Design

### FederatedSubscriptionAgent Interface

```java
public interface FederatedSubscriptionAgent {
    void init(Environment environment, String organization) throws APIManagementException;
    FederatedCredential createSubscription(FederatedSubscriptionRequest request) throws APIManagementException;
    void deleteSubscription(String externalSubscriptionId) throws APIManagementException;
    FederatedCredential regenerateCredential(String externalSubscriptionId) throws APIManagementException;
    InvocationInstruction getInvocationInstruction(String externalApiId) throws APIManagementException;
    default boolean subscriptionExists(String externalSubscriptionId) throws APIManagementException { return true; }
    String getGatewayType();
}
```

---

## Model Classes

### FederatedSubscriptionRequest
- `applicationUuid`, `apiUuid`, `subscriptionUuid` - WSO2 identifiers
- `organizationId`, `environmentId` - Context
- `subscriberId`, `throttlingPolicy` - Subscription details
- `externalApiId`, `externalApplicationId` - External gateway refs
- `additionalParameters` - Gateway-specific params

### FederatedCredential
- `credentialType` - "api-key", "subscription-key", etc.
- `credentialValue` - Full on create/regenerate, masked on get
- `headerName` - Header to use (e.g., "x-api-key")
- `externalSubscriptionId`, `externalContainerId` - External refs
- `createdTime`, `expiresAt` - Timestamps
- `toMasked(int visibleChars)` - Creates masked copy

### InvocationInstruction
- `gatewayType`, `headerName` - Gateway context
- `baseUrl`, `basePath` - Endpoint info
- `additionalHeaders` - Extra required headers
- `curlExample`, `notes` - Developer guidance
- `generateCurlExample(...)` - Utility method

### SubscriptionExternalMapping
- `subscriptionUuid`, `gatewayEnvironmentId` - Primary key
- `externalSubscriptionId`, `externalContainerId` - External refs
- `credentialReference` - Masked credential
- `invocationMetadata` - JSON blob
- `createdTime`, `lastUpdatedTime` - Timestamps

---

## Database Schema

### AM_SUBSCRIPTION_EXTERNAL_MAPPING Table

```sql
CREATE TABLE AM_SUBSCRIPTION_EXTERNAL_MAPPING (
    SUBSCRIPTION_UUID VARCHAR(256) NOT NULL,
    GATEWAY_ENV_ID VARCHAR(255) NOT NULL,
    EXTERNAL_SUBSCRIPTION_ID VARCHAR(512) NOT NULL,
    EXTERNAL_CONTAINER_ID VARCHAR(512),
    CREDENTIAL_REFERENCE VARCHAR(512),
    INVOCATION_METADATA LONGBLOB,
    CREATED_TIME TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    LAST_UPDATED_TIME TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (SUBSCRIPTION_UUID) REFERENCES AM_SUBSCRIPTION(UUID) ON DELETE CASCADE,
    FOREIGN KEY (GATEWAY_ENV_ID) REFERENCES AM_GATEWAY_ENVIRONMENT(UUID),
    PRIMARY KEY (SUBSCRIPTION_UUID, GATEWAY_ENV_ID),
    UNIQUE (EXTERNAL_SUBSCRIPTION_ID, GATEWAY_ENV_ID)
);
```

### DAO Methods to Add
- `addSubscriptionExternalMapping(...)`
- `getSubscriptionExternalMapping(subscriptionUuid, environmentId)`
- `updateSubscriptionExternalMapping(...)`
- `deleteSubscriptionExternalMapping(...)`
- `deleteAllSubscriptionExternalMappings(subscriptionUuid)`
- `getSubscriptionExternalMappings(subscriptionUuid)`
- `subscriptionExternalMappingExists(...)`

### SQL Constants to Add
- `ADD_SUBSCRIPTION_EXTERNAL_MAPPING_SQL`
- `UPDATE_SUBSCRIPTION_EXTERNAL_MAPPING_SQL`
- `GET_SUBSCRIPTION_EXTERNAL_MAPPING_SQL`
- `DELETE_SUBSCRIPTION_EXTERNAL_MAPPING_SQL`
- `DELETE_SUBSCRIPTION_EXTERNAL_MAPPINGS_SQL`
- `GET_SUBSCRIPTION_EXTERNAL_MAPPINGS_SQL`
- `GET_SUBSCRIPTION_BY_EXTERNAL_ID_SQL`
- `CHECK_SUBSCRIPTION_EXTERNAL_MAPPING_EXISTS_SQL`

---

## Factory Pattern

### FederatedSubscriptionAgentFactory

Follow `FederatedApplicationDiscoveryFactory` pattern:
- `ConcurrentHashMap` cache with key `organization:environmentUuid`
- Double-checked locking for thread safety
- Get implementation class from `GatewayAgentConfiguration.getSubscriptionAgentImplementation()`
- Decrypt environment via `APIAdminImpl.decryptGatewayConfigurationValues()`
- Reflection-based instantiation
- Methods: `getSubscriptionAgent()`, `clearSubscriptionAgentCache()`, `clearAllSubscriptionAgentCache()`

---

## GatewayAgentConfiguration Modification

Add method (after `getApplicationDiscoveryImplementation()`):

```java
default String getSubscriptionAgentImplementation() {
    return null;
}
```

---

## Verification

### Build
```bash
cd wso2-carbon-apimgt
mvn clean install -pl components/apimgt/org.wso2.carbon.apimgt.api -am -Dmaven.test.skip=true
mvn clean install -pl components/apimgt/org.wso2.carbon.apimgt.impl -am -Dmaven.test.skip=true
```

### Unit Tests (Future)
- Test model serialization/deserialization
- Test credential masking logic
- Test DAO operations with H2
- Mock factory instantiation

---

## Reference Files

- Interface pattern: `FederatedApplicationDiscovery.java`
- Factory pattern: `FederatedApplicationDiscoveryFactory.java`
- Model pattern: `DiscoveredApplication.java`, `ApplicationExternalMapping.java`
- DAO pattern: `ApiMgtDAO.java` (Application external mapping methods)
- SQL pattern: `mysql.sql` (AM_APPLICATION_EXTERNAL_MAPPING)
