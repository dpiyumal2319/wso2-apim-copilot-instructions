# Implementing Application Discovery in WSO2 APIM

[]: # - **Basic Objects**: Implement `FederatedApplicationDiscovery` and `DiscoveredApplication` Classes.

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

- [ ] Add DAO methods for external mapping persistence — In ApiMgtDAO.java, implement addApplicationExternalMapping, getApplicationExternalMappingByAppId, updateApplicationExternalMapping, deleteApplicationExternalMapping following patterns from addApiExternalApiMapping family of methods.

- [ ] Create DiscoveredApplication DTO and mapping utilities — Add DiscoveredApplicationDTO, DiscoveredApplicationListDTO in org.wso2.carbon.apimgt.rest.api.store.v1.dto, and create DiscoveredApplicationMappingUtil in mappings package with methods for domain-to-DTO conversion following ApplicationMappingUtil patterns.

- [ ] Define REST API specification — In OpenAPI spec for store API, add /environments/{environmentId}/discovered-applications GET endpoint with pagination params (offset, limit, query), and /discovered-applications/import POST endpoint accepting referenceArtifact following patterns from ApplicationsApiServiceImpl.java:126-198.

- [ ] Implement agent factory and loader — Create FederatedApplicationDiscoveryFactory in federated.gateway package to dynamically load agent implementations based on Environment.java gatewayType using reflection pattern from FederatedAPIDiscovery.

### Files Created/Modified

| File | Location | Description |
|------|----------|-------------|
| `DiscoveredApplication.java` | org.wso2.carbon.apimgt.api.model | Main discovered application model with display-safe fields |
| `DiscoveredApplicationKeyInfo.java` | org.wso2.carbon.apimgt.api.model | Credential metadata model with masking support |
| `ApplicationExternalMapping.java` | org.wso2.carbon.apimgt.api.model | External-to-internal application link for tracking imports |
| `DiscoveredApplicationResult.java` | org.wso2.carbon.apimgt.api.model | Pagination wrapper for discovery results |
| `FederatedApplicationDiscovery.java` | org.wso2.carbon.apimgt.api | Enhanced interface with pagination/search/validation methods |

### Further Considerations

- **Database schema approval** — Should we create AM_APPLICATION_EXTERNAL_MAPPING table now or defer until vendor implementation phase? Recommend creating schema early for clean separation. SQL migration script needed for h2.sql, mssql.sql, mysql5.7.sql, oracle.sql, postgresql.sql.

- **Credential security strategy** — For the referenceArtifact JSON, include external credential ID (never the actual key/secret) and masked display names (e.g., "Primary Key: •••••abc"). Actual credential values only retrieved during import via agent's dedicated method. Should we add retrieveCredential(externalId) to FederatedApplicationDiscovery interface?

- **Pagination optimization** — Discovery agents should use native gateway pagination (offset/limit forwarding) to avoid loading large datasets. The interface now supports both getTotalApplicationCount() for accurate counts and hasMore pattern via DiscoveredApplicationResult.

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
