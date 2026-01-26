# Implementing Application Discovery in WSO2 APIM

## 🎯 Executive Summary

**Project Goal:** Enable discovery and import of external gateway applications (Azure APIM Subscriptions, AWS API Gateway Usage Plans) into WSO2 APIM for brownfield migration scenarios.

**Current Status:** 🟢 **~40% Complete - Foundation Ready**

**Architecture Decision:** ✅ Create **AM_APPLICATION_EXTERNAL_MAPPING** table (follows API discovery pattern)
- ❌ NOT using AM_APPLICATION_KEY_MAPPING.APP_INFO (OAuth semantics wrong)
- ❌ NOT using Application.applicationAttributes (no foreign keys, limited structure)
- ✅ NEW dedicated table for clean separation, multi-gateway support, and referential integrity

**Key Insight:** WSO2's API Discovery feature uses AM_API_EXTERNAL_API_MAPPING table. We follow the same proven pattern for applications.

📚 **Documentation:**
- **ANALYSIS.md** - Deep architectural analysis and decision rationale
- **NEXT_STEPS.md** - Implementation guide with code templates
- **AZURE_IMPLEMENTATION.md** - Complete Azure connector documentation

---

## Basic Objects

Plan: Application Discovery - Basic Infrastructure
This plan establishes the foundational interfaces, models, and patterns for discovering external gateway applications and importing them into WSO2 APIM as native Applications. The design follows existing API Discovery patterns while being optimized for manual, stateless discovery with minimal data fetching overhead.

### Steps

- [x] **Enhance DiscoveredApplication.java model** — Add lightweight Application object containing only display/import-essential fields (name, tier, description, attributes), referenceArtifact JSON string with gateway metadata (external ID, tier, credential reference), and credential metadata (masked key names, no secrets).
  - Created: `DiscoveredApplication.java` with fields: externalId, name, description, throttlingTier, owner, createdTime, attributes, keyInfoList, referenceArtifact, alreadyImported, importedApplicationId

- [x] **Create DiscoveredApplicationKeyInfo model** — Model for credential metadata display without exposing secrets.
  - Created: `DiscoveredApplicationKeyInfo.java` with fields: keyType, keyName, maskedKeyValue, externalKeyReference, createdTime, expiryTime, state
  - Includes static `maskKeyValue()` utility method

- [x] **Create ApplicationExternalMapping model class** — In org.wso2.carbon.apimgt.api.model, create model representing the external-to-internal application link containing applicationId, gatewayEnvironmentId, and referenceArtifact following the pattern from API external mapping.
  - Created: `ApplicationExternalMapping.java` with fields: applicationId, applicationUuid, gatewayEnvironmentId, externalApplicationId, referenceArtifact, createdTime, lastUpdatedTime
  - Includes `isExternalApplicationUpdated()` method for change detection

- [x] **Create DiscoveredApplicationResult wrapper** — Pagination result wrapper for discovered applications.
  - Created: `DiscoveredApplicationResult.java` with fields: discoveredApplications, totalCount, offset, limit, hasMoreResults
  - Includes pagination helper methods: getNextOffset(), getPreviousOffset(), getReturnedCount()

- [x] **Enhance FederatedApplicationDiscovery interface** — Add getTotalCount, searchApplications, applicationExists, isApplicationUpdated, getGatewayType methods for complete pagination and validation support.
  - Enhanced with methods: discoverApplications(), discoverApplications(offset, limit, query), discoverApplicationsWithPagination(), getTotalApplicationCount(query), isApplicationUpdated(), getApplication(externalId)

- [x] **Add getApplicationDiscoveryImplementation to GatewayAgentConfiguration** — Register application discovery implementations in gateway configuration.

- [x] **Create SQL migration scripts for AM_APPLICATION_EXTERNAL_MAPPING** — Following AM_API_EXTERNAL_API_MAPPING pattern, create table with columns: APPLICATION_UUID (FK to AM_APPLICATION), GATEWAY_ENV_ID (FK to AM_GATEWAY_ENVIRONMENT), EXTERNAL_APP_ID, REFERENCE_ARTIFACT (LONGBLOB for JSON), CREATED_TIME, LAST_UPDATED_TIME. Add scripts to h2.sql, mysql5.7.sql, postgresql.sql, oracle.sql, mssql.sql.

- [x] **Add SQL constants to SQLConstants.java** — Define ADD_APPLICATION_EXTERNAL_MAPPING_SQL, GET_APPLICATION_EXTERNAL_MAPPING_SQL, UPDATE_APPLICATION_EXTERNAL_MAPPING_SQL, DELETE_APPLICATION_EXTERNAL_MAPPING_SQL, GET_APPLICATION_EXTERNAL_MAPPINGS_SQL following patterns from API external mapping constants (~line 2820).

- [x] **Implement DAO methods in ApiMgtDAO.java** — Add addApplicationExternalMapping(uuid, envId, externalAppId, referenceArtifact), getApplicationExternalMapping(uuid, envId), updateApplicationExternalMapping(...), deleteApplicationExternalMapping(...), getApplicationExternalMappings(uuid) following patterns from addApiExternalApiMapping (~line 16238).

- [x] **Create DiscoveredApplication DTOs** — In org.wso2.carbon.apimgt.rest.api.store.v1.dto, add DiscoveredApplicationDTO (fields: externalId, name, description, tier, owner, createdTime, attributes, keyInfoList, alreadyImported, importedApplicationId), DiscoveredApplicationKeyInfoDTO, DiscoveredApplicationListDTO (with pagination).

- [x] **Create DiscoveredApplicationMappingUtil** — In org.wso2.carbon.apimgt.rest.api.store.v1.mappings, implement fromDiscoveredApplicationToDTO(), fromDiscoveredApplicationListToDTO() following patterns in ApplicationMappingUtil.

- [x] **Define REST API specification in store-api.yaml** — Add endpoints: `GET /environments/{environmentId}/discovered-applications` (query params: offset, limit, query), `POST /discovered-applications/import` (body: referenceArtifact JSON, environmentId). Follow patterns from /applications endpoints.

- [x] **Implement REST service handlers** — In ApplicationsApiServiceImpl.java, add discoverApplications() and importDiscoveredApplication() methods. Discovery calls FederatedApplicationDiscoveryFactory to get agent, import creates Application + ApplicationExternalMapping entries.

- [x] **Create FederatedApplicationDiscoveryFactory** — In org.wso2.carbon.apimgt.impl.federated.gateway, implement factory with loadAgent(Environment env) method using reflection to instantiate azure/aws/other discovery agents based on gatewayType.

### Files Created/Modified

| File | Location | Description |
|------|----------|-------------|
| `DiscoveredApplication.java` | org.wso2.carbon.apimgt.api.model | Main discovered application model with display-safe fields |
| `DiscoveredApplicationKeyInfo.java` | org.wso2.carbon.apimgt.api.model | Credential metadata model with masking support |
| `ApplicationExternalMapping.java` | org.wso2.carbon.apimgt.api.model | External-to-internal application link for tracking imports |
| `DiscoveredApplicationResult.java` | org.wso2.carbon.apimgt.api.model | Pagination wrapper for discovery results |
| `FederatedApplicationDiscovery.java` | org.wso2.carbon.apimgt.api | Enhanced interface with pagination/search/validation methods |

### Further Considerations

- **Database schema decision** ✅ — **DECISION: Create AM_APPLICATION_EXTERNAL_MAPPING table.** Analysis shows this follows the exact pattern used for API discovery (AM_API_EXTERNAL_API_MAPPING). While AM_APPLICATION_KEY_MAPPING.APP_INFO could technically store external references, it overloads semantic meaning and lacks proper foreign keys to gateway environments. Separate table provides clean separation, referential integrity, multi-gateway support, and architectural consistency. See ANALYSIS.md for full rationale.

- **Brownfield key storage strategy** — For Azure brownfield scenarios, REFERENCE_ARTIFACT stores only key references/IDs (never actual secrets). WSO2 generates NEW keys for API subscriptions. Azure keys stay in Azure, fetched on-demand if needed via agent's retrieveCredential() method. AM_APPLICATION_KEY_MAPPING not used for brownfield imports, only for WSO2-generated keys.

- **No modifications to AM_APPLICATION table needed** — Unlike AM_API which has GATEWAY_VENDOR and INITIATED_FROM_GW columns, Applications don't need these flags. The presence of a record in AM_APPLICATION_EXTERNAL_MAPPING table is sufficient to identify imported applications. Application.applicationAttributes can store additional metadata if needed.

- **Pagination optimization** — Discovery agents use native gateway pagination (offset/limit forwarding) to avoid loading large datasets. The interface supports both getTotalApplicationCount() for accurate counts and hasMore pattern via DiscoveredApplicationResult.

---

## Azure Application Federation Connector

**Status:** ✅ **Complete** (All 4 phases implemented)

Azure APIM uses "Subscriptions" as the application concept. The connector maps Azure Subscriptions to WSO2 Applications, extracting throttling tiers from product policies and masking subscription keys during discovery.

### Implementation Summary

- **6 new Java classes** created for discovery, utilities, and data caching
- **4 files modified** for configuration and constants
- **~1,500 lines** of production code
- Maps Azure Subscriptions → WSO2 Applications with tier extraction from product policies
- Server-side pagination with OData filtering support
- Product caching to avoid N+1 query problems
- Secure key handling (masked display, full retrieval only on import)

### Key Components

| Component | Purpose | Status |
|-----------|---------|--------|
| `AzureFederatedApplicationDiscovery` | Main discovery agent | ✅ |
| `AzureApplicationUtil` | Conversion utilities | ✅ |
| `AzureProductDataStore` | Product/tier cache | ✅ |
| `AzurePolicyParser` | Policy XML parser | ✅ |
| `AzureApplicationImportHelper` | Import transformation | ✅ |
| `AzureSubscriptionKeyInfo` | Key metadata model | ✅ |

**📄 Full Implementation Details:** See [AZURE_IMPLEMENTATION.md](./AZURE_IMPLEMENTATION.md) for architecture, entity mapping, reference artifact schema, security considerations, usage examples, and complete technical documentation.
