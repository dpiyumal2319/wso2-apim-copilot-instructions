# Application Discovery Implementation Analysis

## Key Findings from API Discovery Pattern

### 1. Database Architecture - AM_API_EXTERNAL_API_MAPPING

**Table Schema:**
```sql
CREATE TABLE IF NOT EXISTS AM_API_EXTERNAL_API_MAPPING (
    API_ID VARCHAR(255) NOT NULL,
    GATEWAY_ENV_ID VARCHAR(255) NOT NULL,
    REFERENCE_ARTIFACT LONGBLOB NOT NULL,
    FOREIGN KEY (API_ID) REFERENCES AM_API(API_UUID) ON DELETE CASCADE,
    FOREIGN KEY (GATEWAY_ENV_ID) REFERENCES AM_GATEWAY_ENVIRONMENT(UUID),
    PRIMARY KEY (API_ID, GATEWAY_ENV_ID)
);
```

**Purpose:** 
- Tracks which APIs were imported/discovered from external gateways
- Links internal API_UUID to external gateway environment
- Stores gateway-specific metadata in `REFERENCE_ARTIFACT` (JSON blob)
- Enables multi-gateway support (same API can exist in multiple gateways)

### 2. AM_API Table Columns for Gateway Integration

**Columns:**
- `GATEWAY_VENDOR VARCHAR(100) DEFAULT 'wso2'` - Identifies which gateway type (wso2, azure, aws, etc.)
- `INITIATED_FROM_GW INTEGER DEFAULT 0` - Boolean flag (0/1) indicating if API was discovered/imported from external gateway

**Use Cases:**
- Filter APIs by origin (manually created vs imported)
- Apply gateway-specific logic during lifecycle operations
- Prevent certain operations on externally-sourced APIs
- Track provenance for auditing

### 3. AM_APPLICATION_KEY_MAPPING Table

**Table Schema:**
```sql
CREATE TABLE IF NOT EXISTS AM_APPLICATION_KEY_MAPPING (
    UUID VARCHAR(100),
    APPLICATION_ID INTEGER,
    CONSUMER_KEY VARCHAR(512),
    KEY_TYPE VARCHAR(512) NOT NULL,        -- PRODUCTION, SANDBOX
    STATE VARCHAR(30) NOT NULL,
    CREATE_MODE VARCHAR(30) DEFAULT 'CREATED',
    KEY_MANAGER VARCHAR(100),
    APP_INFO BLOB,                         -- JSON blob for additional metadata
    FOREIGN KEY(APPLICATION_ID) REFERENCES AM_APPLICATION(APPLICATION_ID) ON UPDATE CASCADE ON DELETE CASCADE,
    PRIMARY KEY(APPLICATION_ID,KEY_TYPE,KEY_MANAGER)
);
```

**Key Observations:**
- Already supports multiple key managers per application
- `APP_INFO` BLOB field can store arbitrary JSON metadata
- Composite PK allows one app to have PRODUCTION/SANDBOX keys across multiple key managers
- **This table could potentially store external application references in APP_INFO**

### 4. Application Model (Java)

**Current Fields:**
- Standard attributes: id, uuid, name, description, tier, owner, status
- Lifecycle: createdTime, lastUpdatedTime, applicationWorkFlowStatus
- Multi-tenancy: organization, sharedOrganization, subOrganization
- OAuth: keyManagerWiseOAuthApp (Map<keyType, Map<keyManager, OAuthApplicationInfo>>)
- **Custom attributes: `applicationAttributes` (Map<String, String>)**
- Grouping: groupId
- Security: isBlackListed
- Token config: tokenType, callbackUrl

**Key Insight:**
- `applicationAttributes` can store custom key-value pairs
- Could potentially store external references here instead of new table

---

## Architectural Decision: Do We Need AM_APPLICATION_EXTERNAL_MAPPING?

### Option A: Use AM_APPLICATION_KEY_MAPPING.APP_INFO
**Pros:**
- No schema changes required
- Reuses existing infrastructure
- APP_INFO already stores JSON metadata
- Natural fit (external keys are a type of key mapping)

**Cons:**
- Overloads semantic meaning (APP_INFO is for OAuth metadata)
- Requires KEY_TYPE and KEY_MANAGER values (what to use for Azure subscriptions?)
- Could confuse existing code that expects OAuth data in APP_INFO
- Mixing concerns: OAuth credentials vs external gateway references

### Option B: Use Application.applicationAttributes
**Pros:**
- No schema changes
- Simple key-value storage
- Already used for custom metadata

**Cons:**
- Limited structure (flat Map<String, String>)
- Can't store complex JSON easily
- No foreign key to gateway environment
- Single JSON string per attribute key is awkward
- No built-in multi-gateway support

### Option C: Create AM_APPLICATION_EXTERNAL_MAPPING (Recommended)
**Pros:**
- Clean separation of concerns
- Mirrors AM_API_EXTERNAL_API_MAPPING pattern (consistency!)
- Foreign key integrity to gateway environment
- Explicit multi-gateway support
- Can store rich metadata per gateway
- Clear audit trail
- Easier to query/join
- Future-proof for more gateway types

**Cons:**
- Requires schema migration
- More tables to maintain

**Schema:**
```sql
CREATE TABLE IF NOT EXISTS AM_APPLICATION_EXTERNAL_MAPPING (
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

---

## Decision Rationale

### Why AM_APPLICATION_EXTERNAL_MAPPING is the Right Choice

1. **Architectural Consistency**: Follows the exact pattern used for API discovery
2. **Separation of Concerns**: External gateway mapping is distinct from OAuth key management
3. **Multi-Gateway Support**: One WSO2 application can map to Azure subscription + AWS usage plan
4. **Referential Integrity**: Foreign keys ensure data consistency
5. **Query Performance**: Dedicated table with proper indexes
6. **Change Detection**: `LAST_UPDATED_TIME` enables sync logic
7. **Uniqueness**: External apps can only be imported once per gateway
8. **Auditability**: Clear table for compliance/tracking

### What Goes in REFERENCE_ARTIFACT?

For Azure brownfield subscriptions:
```json
{
  "gatewayType": "azure",
  "externalApplicationId": "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ApiManagement/service/{svc}/subscriptions/{id}",
  "subscriptionName": "production-subscription",
  "subscriptionState": "active",
  "productId": "/subscriptions/.../products/unlimited",
  "productName": "Unlimited",
  "tierMapping": {
    "azureProduct": "Unlimited",
    "wso2Tier": "Unlimited"
  },
  "keyReferences": {
    "primaryKey": {
      "keyName": "Primary",
      "externalRef": "/subscriptions/.../subscriptions/{id}/listSecrets",
      "createdTime": "2024-01-15T10:00:00Z"
    },
    "secondaryKey": {
      "keyName": "Secondary", 
      "externalRef": "/subscriptions/.../subscriptions/{id}/listSecrets",
      "createdTime": "2024-01-15T10:00:00Z"
    }
  },
  "importMetadata": {
    "importedAt": "2024-02-01T12:00:00Z",
    "importedBy": "admin@carbon.super",
    "importMode": "brownfield"
  }
}
```

**What NOT to Store:**
- Actual subscription keys (security risk!)
- Full API client credentials
- Only references/IDs needed to fetch keys on-demand

---

## Updated Implementation Plan

### Phase 1: Database Layer ✅ (Partially Complete)
- [x] Define AM_APPLICATION_EXTERNAL_MAPPING schema
- [ ] Create SQL migration scripts (h2, mysql, postgres, oracle, mssql)
- [ ] Add SQL constants to SQLConstants.java
- [ ] Implement DAO methods in ApiMgtDAO.java

### Phase 2: Model Layer ✅ Complete
- [x] ApplicationExternalMapping.java model
- [x] DiscoveredApplication.java
- [x] DiscoveredApplicationKeyInfo.java
- [x] DiscoveredApplicationResult.java
- [x] FederatedApplicationDiscovery interface

### Phase 3: REST API Layer (Next Steps)
- [ ] Define OpenAPI spec for Store API
  - `GET /environments/{envId}/discovered-applications`
  - `POST /discovered-applications/import`
- [ ] Create DTOs (DiscoveredApplicationDTO, etc.)
- [ ] Create MappingUtil (domain ↔ DTO conversion)
- [ ] Implement REST service methods

### Phase 4: Azure Connector ✅ Complete
- [x] AzureFederatedApplicationDiscovery
- [x] Azure-specific utilities
- [x] Product caching
- [x] Policy parsing
- [x] Import transformation

---

## Azure Brownfield Workflow

### 1. Discovery (Read-Only)
```
User → Store API → Discovery Agent → Azure APIM
                    ↓
                List subscriptions with OData pagination
                    ↓
                Fetch product names/policies (cached)
                    ↓
                Mask subscription keys
                    ↓
                Return DiscoveredApplication[]
```

### 2. Import (Write)
```
User selects app → Import API → Discovery Agent
                                    ↓
                            Fetch full subscription details
                                    ↓
                            Retrieve actual keys (if requested)
                                    ↓
                            Create WSO2 Application
                                    ↓
                            Store in AM_APPLICATION
                                    ↓
                            Create AM_APPLICATION_EXTERNAL_MAPPING
                                    ↓
                            Optionally create AM_APPLICATION_KEY_MAPPING
```

### 3. Key Storage Strategy for Brownfield

**Option 1: Reference Only (Recommended for Brownfield)**
- Store only Azure subscription key references in REFERENCE_ARTIFACT
- Don't create AM_APPLICATION_KEY_MAPPING entries
- On API subscription, generate NEW WSO2 keys (standard flow)
- Azure keys stay in Azure, fetched on-demand if needed

**Option 2: Import Keys**
- Fetch actual Azure subscription keys during import
- Create AM_APPLICATION_KEY_MAPPING with Azure keys as CONSUMER_KEY
- Requires custom key manager integration
- More complex, may not be necessary

**Recommendation:** Option 1 for brownfield. The application metadata is imported for tracking/attribution, but WSO2 generates its own keys for API access.

---

## Next Steps

1. **Complete Database Layer**
   - Write SQL migration scripts for all supported databases
   - Add SQL constant definitions
   - Implement full CRUD DAO methods

2. **Build REST API**
   - Define OpenAPI endpoints
   - Create DTOs and mapping utilities
   - Implement service layer

3. **End-to-End Testing**
   - Test discovery flow with Azure connector
   - Test import creating both tables correctly
   - Verify key handling and security
   - Test pagination and filtering

4. **Documentation**
   - API usage examples
   - Configuration guide
   - Security best practices

