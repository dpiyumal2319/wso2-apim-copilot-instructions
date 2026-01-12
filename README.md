# 📊 Application Discovery - Complete Project Overview

## Table of Contents
1. [Project Status](#project-status)
2. [What We Discovered](#what-we-discovered)
3. [Architecture Decisions](#architecture-decisions)
4. [Implementation Roadmap](#implementation-roadmap)
5. [Azure Connector Details](#azure-connector-details)
6. [Next Steps](#next-steps)

---

## 🎯 Project Status

### Progress Tracker
```
█████████████░░░░░░░░░░░░░ 40% Complete

✅ Core Models (100%)
✅ Azure Connector (100%)
✅ Architecture Analysis (100%)
⬜ Database Layer (0%)
⬜ REST API Layer (0%)
⬜ Factory/Loader (0%)
⬜ Testing (0%)
```

### Completion by Phase
| Phase | Status | Completion |
|-------|--------|------------|
| Foundation (Models, Interfaces) | ✅ Done | 100% |
| Azure Connector Implementation | ✅ Done | 100% |
| Architectural Analysis | ✅ Done | 100% |
| Database Schema & DAO | 🔲 Todo | 0% |
| REST API | 🔲 Todo | 0% |
| Integration & Testing | 🔲 Todo | 0% |

---

## 🔍 What We Discovered

### The Critical Question: Do We Need a New Table?

**Short Answer:** YES ✅

**Options Evaluated:**

#### Option 1: Use AM_APPLICATION_KEY_MAPPING.APP_INFO ❌
```
Table Purpose: OAuth credentials (client_id, client_secret)
Our Need: External gateway mapping

Semantic Mismatch: ⚠️⚠️⚠️
- APP_INFO is for OAuth metadata, not gateway references
- KEY_TYPE (PRODUCTION/SANDBOX) doesn't apply to Azure subscriptions
- KEY_MANAGER refers to OAuth providers, not gateways
- Would confuse existing OAuth logic
```

#### Option 2: Use Application.applicationAttributes ❌
```
Type: Map<String, String>

Problems:
- ❌ Flat structure (no nested JSON naturally)
- ❌ No foreign key to GATEWAY_ENVIRONMENT
- ❌ No referential integrity
- ❌ Poor query performance
- ❌ No CREATED_TIME/LAST_UPDATED_TIME per mapping
- ❌ Multi-gateway support awkward
```

#### Option 3: Create AM_APPLICATION_EXTERNAL_MAPPING ✅
```
Historical Precedent: AM_API_EXTERNAL_API_MAPPING

Benefits:
- ✅ Clean separation of concerns
- ✅ Foreign key integrity
- ✅ Multi-gateway support (one app, multiple gateways)
- ✅ Efficient queries with JOINs
- ✅ Change tracking (CREATED_TIME, LAST_UPDATED_TIME)
- ✅ Duplicate prevention (UNIQUE constraint)
- ✅ Follows proven WSO2 pattern
```

### The API Discovery Pattern

**How WSO2 Solved This for APIs:**

1. Created `AM_API_EXTERNAL_API_MAPPING` table
2. No modifications to `AM_API` table (except vendor columns)
3. Used DAO methods following standard patterns
4. Stored gateway metadata in `REFERENCE_ARTIFACT` blob
5. Multi-gateway support via composite primary key

**We're Following the Exact Same Pattern for Applications!**

---

## 🏗️ Architecture Decisions

### Decision #1: Database Schema ✅

**Create New Table:**
```sql
CREATE TABLE AM_APPLICATION_EXTERNAL_MAPPING (
    APPLICATION_UUID VARCHAR(256) NOT NULL,
    GATEWAY_ENV_ID VARCHAR(255) NOT NULL,
    EXTERNAL_APP_ID VARCHAR(512) NOT NULL,
    REFERENCE_ARTIFACT LONGBLOB NOT NULL,
    CREATED_TIME TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    LAST_UPDATED_TIME TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (APPLICATION_UUID) REFERENCES AM_APPLICATION(UUID) ON DELETE CASCADE,
    FOREIGN KEY (GATEWAY_ENV_ID) REFERENCES AM_GATEWAY_ENVIRONMENT(UUID),
    PRIMARY KEY (APPLICATION_UUID, GATEWAY_ENV_ID),
    UNIQUE (EXTERNAL_APP_ID, GATEWAY_ENV_ID)
);
```

**Key Features:**
- Composite PK: (APPLICATION_UUID, GATEWAY_ENV_ID) → One app can map to multiple gateways
- UNIQUE constraint: (EXTERNAL_APP_ID, GATEWAY_ENV_ID) → Prevent duplicate imports
- ON DELETE CASCADE: When app deleted, mappings auto-removed
- LONGBLOB: Supports large JSON artifacts (up to 4GB in MySQL)

### Decision #2: No AM_APPLICATION Modifications ✅

**Unlike AM_API (has GATEWAY_VENDOR, INITIATED_FROM_GW), we DON'T add columns to AM_APPLICATION**

**Why?**
```sql
-- Check if app is imported (simple query):
SELECT 1 FROM AM_APPLICATION_EXTERNAL_MAPPING 
WHERE APPLICATION_UUID = ? 
LIMIT 1;

-- If row exists → imported
-- If no row → native WSO2 app
```

**If needed later, can use:**
```java
// Application.applicationAttributes
app.getApplicationAttributes().put("imported", "true");
app.getApplicationAttributes().put("gatewayVendor", "azure");
```

### Decision #3: Brownfield Key Storage ✅

**For Azure Subscriptions:**

**What We STORE in REFERENCE_ARTIFACT:**
```json
{
  "keyReferences": {
    "primaryKey": {
      "keyName": "Primary",
      "externalRef": "/subscriptions/.../listSecrets",  ← ID only!
      "maskedValue": "••••••••ab12"                     ← Display only!
    }
  }
}
```

**What We DON'T STORE:**
```json
{
  "keyReferences": {
    "primaryKey": {
      "actualKey": "abc123def456..."  ← ❌ NEVER STORE THIS!
    }
  }
}
```

**Why?**
1. Security: No secrets in WSO2 database
2. Simplicity: WSO2 generates NEW keys for API subscriptions
3. Separation: Azure keys stay in Azure
4. On-demand: Fetch via agent's `retrieveCredential()` if needed

### Decision #4: Multi-Gateway Support ✅

**Scenario:**
```
WSO2 Application "MyApp" can link to:
- Azure subscription "prod-sub-123"
- AWS usage plan "prod-plan-456"

Two rows in AM_APPLICATION_EXTERNAL_MAPPING:
┌─────────────┬──────────────┬──────────────────┐
│ APP_UUID    │ GATEWAY_ENV  │ EXTERNAL_APP_ID  │
├─────────────┼──────────────┼──────────────────┤
│ app-uuid-1  │ azure-env-id │ prod-sub-123     │
│ app-uuid-1  │ aws-env-id   │ prod-plan-456    │
└─────────────┴──────────────┴──────────────────┘
```

**Query:**
```java
Map<String, ApplicationExternalMapping> mappings = 
    dao.getApplicationExternalMappings(appUuid);
// Returns: { "azure-env-id" → mapping1, "aws-env-id" → mapping2 }
```

---

## 🗺️ Implementation Roadmap

### Phase 1: Database Layer (HIGH PRIORITY) 🔲

**Tasks:**
1. **Create SQL migration scripts** (5 databases)
   - h2.sql
   - mysql.sql
   - postgresql.sql
   - oracle.sql
   - mssql.sql
   
2. **Add SQL constants** (SQLConstants.java)
   - `ADD_APPLICATION_EXTERNAL_MAPPING_SQL`
   - `GET_APPLICATION_EXTERNAL_MAPPING_SQL`
   - `UPDATE_APPLICATION_EXTERNAL_MAPPING_SQL`
   - `DELETE_APPLICATION_EXTERNAL_MAPPING_SQL`
   - `GET_APPLICATION_EXTERNAL_MAPPINGS_SQL`
   - `GET_APPLICATION_BY_EXTERNAL_APP_ID_SQL`

3. **Implement DAO methods** (ApiMgtDAO.java)
   - `addApplicationExternalMapping(...)`
   - `getApplicationExternalMappingReference(...)`
   - `updateApplicationExternalMapping(...)`
   - `deleteApplicationExternalMapping(...)`
   - `getApplicationExternalMappings(...)`
   - `getApplicationUuidByExternalAppId(...)`

**Reference:** See NEXT_STEPS.md for copy-paste code templates

**Estimated Time:** 4-6 hours

---

### Phase 2: REST API Layer (HIGH PRIORITY) 🔲

**Tasks:**
1. **Define OpenAPI specification** (store-api.yaml)
   ```yaml
   GET /environments/{environmentId}/discovered-applications
   POST /discovered-applications/import
   ```

2. **Create DTOs**
   - `DiscoveredApplicationDTO`
   - `DiscoveredApplicationListDTO`
   - `DiscoveredApplicationKeyInfoDTO`
   - `ApplicationImportRequestDTO`

3. **Create MappingUtil**
   - `DiscoveredApplicationMappingUtil.java`
   - Methods: `fromDiscoveredApplicationToDTO()`, `fromListToDTO()`

4. **Implement service handlers** (ApplicationsApiServiceImpl.java)
   - `getDiscoveredApplications()`
   - `importDiscoveredApplication()`

**Reference:** See NEXT_STEPS.md for OpenAPI spec template

**Estimated Time:** 6-8 hours

---

### Phase 3: Factory & Loader (MEDIUM PRIORITY) 🔲

**Tasks:**
1. **Create FederatedApplicationDiscoveryFactory**
   ```java
   public static FederatedApplicationDiscovery loadAgent(Environment env) {
       String gatewayType = env.getGatewayType();
       String className = "org.wso2.carbon.apimgt.impl.federated.gateway." + 
                         gatewayType + ".FederatedApplicationDiscovery";
       return (FederatedApplicationDiscovery) Class.forName(className).newInstance();
   }
   ```

2. **Configure agent registration**
   - Map gateway types to agent class names
   - Similar to FederatedAPIDiscovery pattern

**Estimated Time:** 2-3 hours

---

### Phase 4: Integration & Testing (CRITICAL) 🔲

**Test Cases:**
1. **Database Tests**
   - ✓ SQL scripts execute without errors
   - ✓ DAO can create/read/update/delete mappings
   - ✓ Foreign key constraints work
   - ✓ UNIQUE constraint prevents duplicates

2. **Discovery Tests**
   - ✓ Azure connector discovers applications
   - ✓ Pagination works correctly
   - ✓ Filtering by query works
   - ✓ Keys are properly masked

3. **Import Tests**
   - ✓ Import creates Application record
   - ✓ Import creates ExternalMapping record
   - ✓ Duplicate import is rejected
   - ✓ REFERENCE_ARTIFACT is stored correctly

4. **Security Tests**
   - ✓ No secrets in API responses
   - ✓ No secrets in database
   - ✓ Masked values display correctly

5. **Multi-Gateway Tests**
   - ✓ One app can have multiple mappings
   - ✓ Query returns all mappings
   - ✓ Delete app removes all mappings

**Estimated Time:** 8-10 hours

---

## 🔵 Azure Connector Details

### Status: ✅ 100% Complete

**Implementation Summary:**
- 6 new Java classes (~1,500 lines)
- Maps Azure Subscriptions → WSO2 Applications
- Extracts throttling tiers from product policies
- Server-side pagination with OData
- Product caching (N+1 prevention)
- Secure key handling (masking)

### Key Components

| Component | Purpose | Lines | Status |
|-----------|---------|-------|--------|
| AzureFederatedApplicationDiscovery | Main agent | ~400 | ✅ |
| AzureApplicationUtil | Conversions | ~200 | ✅ |
| AzureProductDataStore | Caching | ~150 | ✅ |
| AzurePolicyParser | XML parsing | ~250 | ✅ |
| AzureApplicationImportHelper | Import logic | ~300 | ✅ |
| AzureSubscriptionKeyInfo | Key metadata | ~100 | ✅ |

### Azure Mapping

**Azure Entity → WSO2 Entity:**
```
Azure Subscription ───────→ WSO2 Application
├─ Subscription Name      → Application.name
├─ Display Name           → Application.description
├─ State (active/...)     → Application.status
├─ Owner ID               → Application.owner
├─ Product → Policy       → Application.tier (extracted!)
├─ Primary Key            → DiscoveredApplicationKeyInfo (masked)
└─ Secondary Key          → DiscoveredApplicationKeyInfo (masked)
```

### Reference Artifact Schema

**Complete JSON structure stored in REFERENCE_ARTIFACT:**
```json
{
  "gatewayType": "azure",
  "externalApplicationId": "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ApiManagement/service/{svc}/subscriptions/{id}",
  "subscriptionName": "production-subscription",
  "subscriptionDisplayName": "Production API Subscription",
  "subscriptionState": "active",
  "subscriptionScope": "/products/unlimited",
  "productId": "/subscriptions/.../products/unlimited",
  "productName": "Unlimited",
  "productDescription": "Unlimited product for testing",
  "tierMapping": {
    "azureProductName": "Unlimited",
    "azurePolicyXml": "<policies><inbound><rate-limit-by-key...</inbound></policies>",
    "extractedTier": "Unlimited",
    "wso2Tier": "Unlimited"
  },
  "keyReferences": {
    "primaryKey": {
      "keyName": "Primary",
      "keyType": "PRIMARY",
      "externalRef": "/subscriptions/.../subscriptions/{id}/listSecrets",
      "maskedValue": "••••••••••••ab12",
      "createdTime": "2024-01-15T10:00:00Z",
      "expiryTime": null,
      "state": "active"
    },
    "secondaryKey": {
      "keyName": "Secondary",
      "keyType": "SECONDARY",
      "externalRef": "/subscriptions/.../subscriptions/{id}/listSecrets",
      "maskedValue": "••••••••••••cd34",
      "createdTime": "2024-01-15T10:00:00Z",
      "expiryTime": null,
      "state": "active"
    }
  },
  "importMetadata": {
    "importedAt": "2024-02-01T12:00:00Z",
    "importedBy": "admin@carbon.super",
    "importMode": "brownfield",
    "wso2ApplicationUuid": "abc-123-def-456",
    "wso2ApplicationId": 42,
    "discoveryTimestamp": "2024-02-01T11:55:00Z"
  },
  "azureResourceMetadata": {
    "subscriptionId": "{azure-subscription-id}",
    "resourceGroup": "{resource-group}",
    "serviceName": "{apim-service-name}",
    "managementEndpoint": "https://{service}.management.azure-api.net",
    "gatewayEndpoint": "https://{service}.azure-api.net"
  }
}
```

**Size Estimate:** 1-2 KB per application

---

## 🚀 Next Steps (Priority Order)

### Immediate (Week 1)
1. ✏️ Create SQL migration scripts
   - Start with h2.sql
   - Test locally with H2 database
   - Adapt for other databases

2. ✏️ Add SQL constants to SQLConstants.java
   - 6 constant definitions
   - Follow existing patterns

3. ✏️ Implement DAO methods in ApiMgtDAO.java
   - 6 methods
   - Copy pattern from `addApiExternalApiMapping`

### Short-term (Week 2)
4. ✏️ Define REST API OpenAPI spec
   - 2 endpoints
   - 4 DTOs
   - Add to store-api.yaml

5. ✏️ Implement MappingUtil
   - Domain → DTO conversion
   - List pagination support

6. ✏️ Implement service handlers
   - Discovery flow
   - Import flow

### Medium-term (Week 3)
7. ✏️ Create Factory/Loader
   - Agent registration
   - Reflection-based loading

8. ✏️ End-to-end testing
   - Database tests
   - REST API tests
   - Azure integration tests
   - Security tests

### Long-term (Future)
9. 🔮 AWS connector implementation
10. 🔮 Kong connector implementation
11. 🔮 Automated sync (if external app changes)

---

## 📚 Reference Documents

| Document | Purpose |
|----------|---------|
| **plan.md** | Master implementation plan with task checklist |
| **ANALYSIS.md** | Deep architectural analysis and rationale |
| **NEXT_STEPS.md** | Code templates and implementation guide |
| **AZURE_IMPLEMENTATION.md** | Complete Azure connector documentation |
| **answers.md** | FAQ answering all architectural questions |
| **README.md** | Project overview (create this next?) |

---

## 📊 Key Metrics

### Code Statistics
- **New Java Classes:** 11 (6 Azure + 5 Core Models)
- **Lines of Code:** ~2,000
- **SQL Scripts:** 5 databases
- **REST Endpoints:** 2
- **DTOs:** 4+
- **DAO Methods:** 6

### Test Coverage Goals
- Unit Tests: 80%+
- Integration Tests: Key flows
- Security Tests: All endpoints
- Performance Tests: Pagination with 10,000+ apps

---

## ✅ Success Criteria

**Discovery:**
- [ ] Can list Azure subscriptions via REST API
- [ ] Pagination works correctly
- [ ] Keys are masked in responses
- [ ] Already-imported apps are marked correctly

**Import:**
- [ ] Can import discovered application
- [ ] Creates Application record
- [ ] Creates ExternalMapping record
- [ ] REFERENCE_ARTIFACT stored correctly
- [ ] Duplicate import is prevented

**Security:**
- [ ] No secrets in API responses
- [ ] No secrets in database
- [ ] Only masked values displayed

**Performance:**
- [ ] Discovery with 1,000+ apps completes in <5s
- [ ] Import completes in <2s
- [ ] Database queries optimized with indexes

---

## 🎯 Conclusion

**We're at a great place!**

✅ All architectural questions answered
✅ All design decisions documented
✅ Core models implemented
✅ Azure connector complete
✅ Clear implementation path ahead

**Next action: Start with SQL scripts** (see NEXT_STEPS.md for templates)

**Estimated time to MVP: 2-3 weeks** with one full-time developer familiar with WSO2 APIM codebase.

---

## 📞 Questions or Issues?

Refer to:
1. **ANALYSIS.md** - Why we made architectural decisions
2. **NEXT_STEPS.md** - How to implement remaining tasks
3. **answers.md** - Common questions answered

**Happy coding! 🚀**

