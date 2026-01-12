# 🚀 Quick Start Implementation Guide

This guide will get you started implementing the remaining 60% of the Application Discovery feature.

---

## ⚡ 5-Minute Overview

**What we're building:**
- Discovery: List Azure APIM subscriptions via REST API
- Import: Create WSO2 Application linked to Azure subscription
- Tracking: New table AM_APPLICATION_EXTERNAL_MAPPING

**What's done:**
- ✅ Core models (DiscoveredApplication, etc.)
- ✅ Azure connector (100% complete)
- ✅ Architecture decisions

**What's needed:**
- 🔲 SQL table creation (5 databases)
- 🔲 DAO methods (6 methods)
- 🔲 REST API (2 endpoints)
- 🔲 DTOs & mapping (4 classes)

---

## 🎯 Implementation Steps

### Step 1: Create SQL Table (30 minutes)

**Location:** `wso2-carbon-apimgt/features/apimgt/org.wso2.carbon.apimgt.core.feature/src/main/resources/sql/h2.sql`

**Find this line (~2360):**
```sql
CREATE TABLE IF NOT EXISTS AM_API_EXTERNAL_API_MAPPING (
    API_ID VARCHAR(255) NOT NULL,
    ...
);
```

**Add after it:**
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

**Repeat for:** mysql.sql, postgresql.sql, oracle.sql, mssql.sql
_(See NEXT_STEPS.md for database-specific syntax)_

---

### Step 2: Add SQL Constants (15 minutes)

**Location:** `wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.impl/src/main/java/org/wso2/carbon/apimgt/impl/dao/constants/SQLConstants.java`

**Find this section (~2820):**
```java
// API External Mapping SQL Statements
public static final String ADD_API_EXTERNAL_API_MAPPING_SQL = ...
```

**Add after it:**
```java
// Application External Mapping SQL Statements
public static final String ADD_APPLICATION_EXTERNAL_MAPPING_SQL = 
    "INSERT INTO AM_APPLICATION_EXTERNAL_MAPPING " +
    "(APPLICATION_UUID, GATEWAY_ENV_ID, EXTERNAL_APP_ID, REFERENCE_ARTIFACT) VALUES (?, ?, ?, ?)";

public static final String GET_APPLICATION_EXTERNAL_MAPPING_SQL = 
    "SELECT REFERENCE_ARTIFACT FROM AM_APPLICATION_EXTERNAL_MAPPING " +
    "WHERE APPLICATION_UUID = ? AND GATEWAY_ENV_ID = ?";

public static final String UPDATE_APPLICATION_EXTERNAL_MAPPING_SQL = 
    "UPDATE AM_APPLICATION_EXTERNAL_MAPPING SET REFERENCE_ARTIFACT = ?, " +
    "LAST_UPDATED_TIME = ? WHERE APPLICATION_UUID = ? AND GATEWAY_ENV_ID = ?";

public static final String DELETE_APPLICATION_EXTERNAL_MAPPING_SQL = 
    "DELETE FROM AM_APPLICATION_EXTERNAL_MAPPING " +
    "WHERE APPLICATION_UUID = ? AND GATEWAY_ENV_ID = ?";

public static final String DELETE_APPLICATION_EXTERNAL_MAPPINGS_SQL = 
    "DELETE FROM AM_APPLICATION_EXTERNAL_MAPPING WHERE APPLICATION_UUID = ?";

public static final String GET_APPLICATION_EXTERNAL_MAPPINGS_SQL = 
    "SELECT GATEWAY_ENV_ID, EXTERNAL_APP_ID, REFERENCE_ARTIFACT, CREATED_TIME, LAST_UPDATED_TIME " +
    "FROM AM_APPLICATION_EXTERNAL_MAPPING WHERE APPLICATION_UUID = ?";

public static final String GET_APPLICATION_BY_EXTERNAL_APP_ID_SQL = 
    "SELECT APPLICATION_UUID FROM AM_APPLICATION_EXTERNAL_MAPPING " +
    "WHERE EXTERNAL_APP_ID = ? AND GATEWAY_ENV_ID = ?";
```

---

### Step 3: Add DAO Methods (1 hour)

**Location:** `wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.impl/src/main/java/org/wso2/carbon/apimgt/impl/dao/ApiMgtDAO.java`

**Find this method (~16238):**
```java
public void addApiExternalApiMapping(String apiId, ...) {
    ...
}
```

**Add similar methods for applications:**

See NEXT_STEPS.md for complete code (6 methods, ~200 lines total)

**Quick version of first method:**
```java
public void addApplicationExternalMapping(String applicationUuid, String environmentId, 
                                           String externalAppId, String referenceArtifact) 
        throws APIManagementException {
    try (Connection connection = APIMgtDBUtil.getConnection();
         PreparedStatement ps = connection.prepareStatement(
             SQLConstants.ADD_APPLICATION_EXTERNAL_MAPPING_SQL)) {
        
        connection.setAutoCommit(false);
        ps.setString(1, applicationUuid);
        ps.setString(2, environmentId);
        ps.setString(3, externalAppId);
        ps.setBytes(4, referenceArtifact.getBytes(StandardCharsets.UTF_8));
        ps.executeUpdate();
        connection.commit();
        
    } catch (SQLException e) {
        handleException("Error while adding application external mapping", e);
    }
}
```

**Don't forget imports:**
```java
import org.apache.commons.io.IOUtils;
import java.nio.charset.StandardCharsets;
import org.wso2.carbon.apimgt.api.model.ApplicationExternalMapping;
```

---

### Step 4: Define REST API (30 minutes)

**Location:** `wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.rest.api.store.v1/src/main/resources/store-api.yaml`

**Find the /applications section, add:**

```yaml
  /environments/{environmentId}/discovered-applications:
    get:
      tags:
        - Applications
      summary: Get discovered applications from external gateway
      operationId: getDiscoveredApplications
      parameters:
        - name: environmentId
          in: path
          required: true
          schema:
            type: string
        - $ref: '#/components/parameters/limit'
        - $ref: '#/components/parameters/offset'
        - name: query
          in: query
          schema:
            type: string
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/DiscoveredApplicationList'
      security:
        - OAuth2Security:
            - apim:subscribe

  /discovered-applications/import:
    post:
      tags:
        - Applications
      summary: Import discovered application
      operationId: importDiscoveredApplication
      requestBody:
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/ApplicationImportRequest'
        required: true
      responses:
        '201':
          description: Created
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Application'
      security:
        - OAuth2Security:
            - apim:subscribe
```

**In components/schemas section, add:**
```yaml
    DiscoveredApplicationList:
      type: object
      properties:
        count:
          type: integer
        list:
          type: array
          items:
            $ref: '#/components/schemas/DiscoveredApplication'
        pagination:
          $ref: '#/components/schemas/Pagination'

    DiscoveredApplication:
      type: object
      properties:
        externalId:
          type: string
        name:
          type: string
        description:
          type: string
        throttlingTier:
          type: string
        owner:
          type: string
        keyInfo:
          type: array
          items:
            $ref: '#/components/schemas/DiscoveredApplicationKeyInfo'
        alreadyImported:
          type: boolean
        referenceArtifact:
          type: string

    DiscoveredApplicationKeyInfo:
      type: object
      properties:
        keyName:
          type: string
        maskedKeyValue:
          type: string
        keyType:
          type: string

    ApplicationImportRequest:
      type: object
      required:
        - environmentId
        - referenceArtifact
      properties:
        environmentId:
          type: string
        referenceArtifact:
          type: string
```

---

### Step 5: Generate DTOs (5 minutes)

**Run Maven to generate DTOs from OpenAPI spec:**

```bash
cd wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.rest.api.store.v1
mvn clean install -DskipTests
```

**This generates:**
- DiscoveredApplicationDTO.java
- DiscoveredApplicationListDTO.java
- DiscoveredApplicationKeyInfoDTO.java
- ApplicationImportRequestDTO.java

---

### Step 6: Create MappingUtil (30 minutes)

**Location:** Create new file `wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.rest.api.store.v1/src/main/java/org/wso2/carbon/apimgt/rest/api/store/v1/mappings/DiscoveredApplicationMappingUtil.java`

```java
package org.wso2.carbon.apimgt.rest.api.store.v1.mappings;

import org.wso2.carbon.apimgt.api.model.DiscoveredApplication;
import org.wso2.carbon.apimgt.api.model.DiscoveredApplicationKeyInfo;
import org.wso2.carbon.apimgt.api.model.DiscoveredApplicationResult;
import org.wso2.carbon.apimgt.rest.api.store.v1.dto.*;

import java.util.ArrayList;
import java.util.List;

public class DiscoveredApplicationMappingUtil {

    public static DiscoveredApplicationDTO fromDiscoveredApplicationToDTO(
            DiscoveredApplication application) {
        
        DiscoveredApplicationDTO dto = new DiscoveredApplicationDTO();
        dto.setExternalId(application.getExternalId());
        dto.setName(application.getName());
        dto.setDescription(application.getDescription());
        dto.setThrottlingTier(application.getThrottlingTier());
        dto.setOwner(application.getOwner());
        dto.setAlreadyImported(application.isAlreadyImported());
        dto.setReferenceArtifact(application.getReferenceArtifact());
        
        // Map key info
        List<DiscoveredApplicationKeyInfoDTO> keyInfoDTOs = new ArrayList<>();
        for (DiscoveredApplicationKeyInfo keyInfo : application.getKeyInfoList()) {
            DiscoveredApplicationKeyInfoDTO keyInfoDTO = new DiscoveredApplicationKeyInfoDTO();
            keyInfoDTO.setKeyName(keyInfo.getKeyName());
            keyInfoDTO.setKeyType(keyInfo.getKeyType());
            keyInfoDTO.setMaskedKeyValue(keyInfo.getMaskedKeyValue());
            keyInfoDTOs.add(keyInfoDTO);
        }
        dto.setKeyInfo(keyInfoDTOs);
        
        return dto;
    }

    public static DiscoveredApplicationListDTO fromDiscoveredApplicationListToDTO(
            DiscoveredApplicationResult result) {
        
        DiscoveredApplicationListDTO listDTO = new DiscoveredApplicationListDTO();
        listDTO.setCount(result.getReturnedCount());
        
        List<DiscoveredApplicationDTO> appDTOs = new ArrayList<>();
        for (DiscoveredApplication app : result.getDiscoveredApplications()) {
            appDTOs.add(fromDiscoveredApplicationToDTO(app));
        }
        listDTO.setList(appDTOs);
        
        // Pagination
        PaginationDTO pagination = new PaginationDTO();
        pagination.setOffset(result.getOffset());
        pagination.setLimit(result.getLimit());
        pagination.setTotal(result.getTotalCount());
        if (result.hasMoreResults()) {
            pagination.setNext("?offset=" + result.getNextOffset() + "&limit=" + result.getLimit());
        }
        if (result.getOffset() > 0) {
            pagination.setPrevious("?offset=" + result.getPreviousOffset() + "&limit=" + result.getLimit());
        }
        listDTO.setPagination(pagination);
        
        return listDTO;
    }
}
```

---

### Step 7: Implement Service Handlers (1 hour)

**Location:** `wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.rest.api.store.v1/src/main/java/org/wso2/carbon/apimgt/rest/api/store/v1/impl/ApplicationsApiServiceImpl.java`

**Add these methods:**

```java
@Override
public Response getDiscoveredApplications(String environmentId, Integer limit, Integer offset, 
                                           String query, MessageContext messageContext) {
    try {
        // Get gateway environment
        Environment environment = APIUtil.getEnvironment(environmentId);
        if (environment == null) {
            RestApiUtil.handleResourceNotFoundError("Gateway environment not found", log);
        }
        
        // Load discovery agent
        FederatedApplicationDiscovery discoveryAgent = 
            FederatedApplicationDiscoveryFactory.loadAgent(environment);
        
        // Discover applications
        DiscoveredApplicationResult result = discoveryAgent.discoverApplicationsWithPagination(
            offset != null ? offset : 0,
            limit != null ? limit : 25,
            query
        );
        
        // Check which apps are already imported
        ApiMgtDAO dao = ApiMgtDAO.getInstance();
        for (DiscoveredApplication app : result.getDiscoveredApplications()) {
            String appUuid = dao.getApplicationUuidByExternalAppId(
                app.getExternalId(), environmentId
            );
            if (appUuid != null) {
                app.setAlreadyImported(true);
                app.setImportedApplicationId(appUuid);
            }
        }
        
        // Convert to DTO
        DiscoveredApplicationListDTO dto = 
            DiscoveredApplicationMappingUtil.fromDiscoveredApplicationListToDTO(result);
        
        return Response.ok().entity(dto).build();
        
    } catch (APIManagementException e) {
        RestApiUtil.handleInternalServerError("Error discovering applications", e, log);
    }
    return null;
}

@Override
public Response importDiscoveredApplication(ApplicationImportRequestDTO body, 
                                             MessageContext messageContext) {
    try {
        String username = RestApiUtil.getLoggedInUsername();
        String organization = RestApiUtil.getOrganization(messageContext);
        
        // Get gateway environment
        Environment environment = APIUtil.getEnvironment(body.getEnvironmentId());
        if (environment == null) {
            RestApiUtil.handleResourceNotFoundError("Gateway environment not found", log);
        }
        
        // Load discovery agent
        FederatedApplicationDiscovery discoveryAgent = 
            FederatedApplicationDiscoveryFactory.loadAgent(environment);
        
        // Parse reference artifact to get external ID
        JSONObject artifact = new JSONObject(body.getReferenceArtifact());
        String externalAppId = artifact.getString("externalApplicationId");
        
        // Check if already imported
        ApiMgtDAO dao = ApiMgtDAO.getInstance();
        String existingUuid = dao.getApplicationUuidByExternalAppId(
            externalAppId, body.getEnvironmentId()
        );
        if (existingUuid != null) {
            RestApiUtil.handleResourceAlreadyExistsError(
                "Application already imported", log
            );
        }
        
        // Get application details
        DiscoveredApplication discoveredApp = discoveryAgent.getApplication(externalAppId);
        
        // Create WSO2 application
        Application application = new Application(discoveredApp.getName(), username);
        application.setDescription(discoveredApp.getDescription());
        application.setTier(discoveredApp.getThrottlingTier());
        application.setOwner(username);
        application.setOrganization(organization);
        
        // Add application
        APIProvider apiProvider = RestApiCommonUtil.getLoggedInUserProvider();
        int applicationId = apiProvider.addApplication(application, username, organization);
        application = apiProvider.getApplicationById(applicationId);
        
        // Add external mapping
        dao.addApplicationExternalMapping(
            application.getUUID(),
            body.getEnvironmentId(),
            externalAppId,
            body.getReferenceArtifact()
        );
        
        // Convert to DTO
        ApplicationDTO dto = ApplicationMappingUtil.fromApplicationToDTO(application);
        
        return Response.status(Response.Status.CREATED).entity(dto).build();
        
    } catch (APIManagementException e) {
        RestApiUtil.handleInternalServerError("Error importing application", e, log);
    }
    return null;
}
```

**Add imports:**
```java
import org.wso2.carbon.apimgt.api.federated.gateway.FederatedApplicationDiscovery;
import org.wso2.carbon.apimgt.impl.federated.gateway.FederatedApplicationDiscoveryFactory;
import org.wso2.carbon.apimgt.api.model.DiscoveredApplication;
import org.wso2.carbon.apimgt.api.model.DiscoveredApplicationResult;
import org.wso2.carbon.apimgt.rest.api.store.v1.mappings.DiscoveredApplicationMappingUtil;
import org.json.JSONObject;
```

---

### Step 8: Create Factory (30 minutes)

**Location:** Create new file `wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.impl/src/main/java/org/wso2/carbon/apimgt/impl/federated/gateway/FederatedApplicationDiscoveryFactory.java`

```java
package org.wso2.carbon.apimgt.impl.federated.gateway;

import org.wso2.carbon.apimgt.api.APIManagementException;
import org.wso2.carbon.apimgt.api.federated.gateway.FederatedApplicationDiscovery;
import org.wso2.carbon.apimgt.api.model.Environment;

public class FederatedApplicationDiscoveryFactory {

    private static final String PACKAGE_PREFIX = 
        "org.wso2.carbon.apimgt.impl.federated.gateway.";

    public static FederatedApplicationDiscovery loadAgent(Environment environment) 
            throws APIManagementException {
        
        String gatewayType = environment.getGatewayType();
        if (gatewayType == null || gatewayType.isEmpty()) {
            throw new APIManagementException("Gateway type not specified");
        }
        
        try {
            // Build class name: org.wso2...gateway.azure.AzureFederatedApplicationDiscovery
            String className = PACKAGE_PREFIX + 
                               gatewayType.toLowerCase() + "." + 
                               capitalize(gatewayType) + "FederatedApplicationDiscovery";
            
            // Load class
            Class<?> agentClass = Class.forName(className);
            
            // Create instance
            FederatedApplicationDiscovery agent = 
                (FederatedApplicationDiscovery) agentClass.newInstance();
            
            // Initialize with environment config
            agent.initialize(environment);
            
            return agent;
            
        } catch (ClassNotFoundException e) {
            throw new APIManagementException(
                "Discovery agent not found for gateway type: " + gatewayType, e
            );
        } catch (Exception e) {
            throw new APIManagementException(
                "Error loading discovery agent for gateway type: " + gatewayType, e
            );
        }
    }
    
    private static String capitalize(String str) {
        if (str == null || str.isEmpty()) {
            return str;
        }
        return str.substring(0, 1).toUpperCase() + str.substring(1).toLowerCase();
    }
}
```

---

### Step 9: Build & Test (30 minutes)

**Build the project:**
```bash
cd wso2-carbon-apimgt
mvn clean install -DskipTests
```

**Start WSO2 APIM:**
```bash
cd wso2am/bin
./api-manager.sh
```

**Test discovery endpoint:**
```bash
curl -H "Authorization: Bearer <token>" \
  "https://localhost:9443/api/am/devportal/v3/environments/azure-env-uuid/discovered-applications?offset=0&limit=10"
```

**Expected response:**
```json
{
  "count": 10,
  "list": [
    {
      "externalId": "subscription-123",
      "name": "Production Subscription",
      "description": "...",
      "throttlingTier": "Unlimited",
      "keyInfo": [
        {
          "keyName": "Primary",
          "maskedKeyValue": "••••••••ab12",
          "keyType": "PRIMARY"
        }
      ],
      "alreadyImported": false,
      "referenceArtifact": "{...}"
    }
  ],
  "pagination": {
    "offset": 0,
    "limit": 10,
    "total": 42
  }
}
```

---

## ✅ Verification Checklist

- [ ] SQL table created in all 5 databases
- [ ] SQL constants added to SQLConstants.java
- [ ] DAO methods implemented in ApiMgtDAO.java
- [ ] OpenAPI spec updated in store-api.yaml
- [ ] DTOs generated successfully
- [ ] MappingUtil created
- [ ] Service handlers implemented
- [ ] Factory created
- [ ] Project builds without errors
- [ ] Discovery endpoint returns applications
- [ ] Keys are masked in response
- [ ] Import endpoint creates application
- [ ] Import endpoint creates external mapping
- [ ] Duplicate import is rejected

---

## 🐛 Troubleshooting

**Build fails with missing imports:**
```
Solution: Make sure you added all required imports in each file
```

**Discovery endpoint returns 404:**
```
Solution: Check gateway environment UUID is correct
Solution: Verify factory can load Azure agent
```

**Import fails with foreign key error:**
```
Solution: Verify application UUID exists in AM_APPLICATION
Solution: Verify gateway environment UUID exists in AM_GATEWAY_ENVIRONMENT
```

**Keys visible in API response:**
```
Solution: Check DiscoveredApplicationKeyInfo.maskKeyValue() is called
Solution: Verify referenceArtifact doesn't contain actual keys
```

---

## 📚 Reference

- **NEXT_STEPS.md** - Complete code templates
- **ANALYSIS.md** - Architectural decisions
- **README.md** - Project overview

---

## 🎉 Success!

Once all steps are complete, you'll have:
- ✅ Full discovery flow working
- ✅ Import flow creating apps + mappings
- ✅ Security (no secrets leaked)
- ✅ Multi-gateway support
- ✅ Azure connector integrated

**Happy coding! 🚀**

