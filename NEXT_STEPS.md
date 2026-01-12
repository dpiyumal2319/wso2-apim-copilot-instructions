# 🔨 Implementation Guide: Next Steps

This guide provides copy-paste-ready patterns for implementing the remaining components.

---

## 1️⃣ SQL Migration Scripts

### Location
`wso2-carbon-apimgt/features/apimgt/org.wso2.carbon.apimgt.core.feature/src/main/resources/sql/`

### Files to Modify
- `h2.sql`
- `mysql.sql` or `mysql5.7.sql`
- `postgresql.sql`
- `oracle.sql`
- `mssql.sql`

### SQL to Add (After AM_API_EXTERNAL_API_MAPPING)

**H2:**
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

**MySQL:**
```sql
CREATE TABLE IF NOT EXISTS AM_APPLICATION_EXTERNAL_MAPPING (
    APPLICATION_UUID VARCHAR(256) NOT NULL,
    GATEWAY_ENV_ID VARCHAR(255) NOT NULL,
    EXTERNAL_APP_ID VARCHAR(512) NOT NULL,
    REFERENCE_ARTIFACT LONGBLOB NOT NULL,
    CREATED_TIME TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    LAST_UPDATED_TIME TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (APPLICATION_UUID) REFERENCES AM_APPLICATION(UUID) ON DELETE CASCADE,
    FOREIGN KEY (GATEWAY_ENV_ID) REFERENCES AM_GATEWAY_ENVIRONMENT(UUID),
    PRIMARY KEY (APPLICATION_UUID, GATEWAY_ENV_ID),
    UNIQUE KEY (EXTERNAL_APP_ID, GATEWAY_ENV_ID)
) ENGINE=InnoDB;
```

**PostgreSQL:**
```sql
CREATE TABLE IF NOT EXISTS AM_APPLICATION_EXTERNAL_MAPPING (
    APPLICATION_UUID VARCHAR(256) NOT NULL,
    GATEWAY_ENV_ID VARCHAR(255) NOT NULL,
    EXTERNAL_APP_ID VARCHAR(512) NOT NULL,
    REFERENCE_ARTIFACT BYTEA NOT NULL,
    CREATED_TIME TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    LAST_UPDATED_TIME TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (APPLICATION_UUID) REFERENCES AM_APPLICATION(UUID) ON DELETE CASCADE,
    FOREIGN KEY (GATEWAY_ENV_ID) REFERENCES AM_GATEWAY_ENVIRONMENT(UUID),
    PRIMARY KEY (APPLICATION_UUID, GATEWAY_ENV_ID),
    UNIQUE (EXTERNAL_APP_ID, GATEWAY_ENV_ID)
);
```

**Oracle:**
```sql
CREATE TABLE AM_APPLICATION_EXTERNAL_MAPPING (
    APPLICATION_UUID VARCHAR2(256) NOT NULL,
    GATEWAY_ENV_ID VARCHAR2(255) NOT NULL,
    EXTERNAL_APP_ID VARCHAR2(512) NOT NULL,
    REFERENCE_ARTIFACT BLOB NOT NULL,
    CREATED_TIME TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    LAST_UPDATED_TIME TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (APPLICATION_UUID) REFERENCES AM_APPLICATION(UUID) ON DELETE CASCADE,
    FOREIGN KEY (GATEWAY_ENV_ID) REFERENCES AM_GATEWAY_ENVIRONMENT(UUID),
    PRIMARY KEY (APPLICATION_UUID, GATEWAY_ENV_ID),
    UNIQUE (EXTERNAL_APP_ID, GATEWAY_ENV_ID)
)
/
```

**MSSQL:**
```sql
IF NOT EXISTS (SELECT * FROM SYS.OBJECTS WHERE OBJECT_ID = OBJECT_ID(N'[DBO].[AM_APPLICATION_EXTERNAL_MAPPING]') AND TYPE IN (N'U'))
CREATE TABLE AM_APPLICATION_EXTERNAL_MAPPING (
    APPLICATION_UUID VARCHAR(256) NOT NULL,
    GATEWAY_ENV_ID VARCHAR(255) NOT NULL,
    EXTERNAL_APP_ID VARCHAR(512) NOT NULL,
    REFERENCE_ARTIFACT VARBINARY(MAX) NOT NULL,
    CREATED_TIME DATETIME DEFAULT GETDATE(),
    LAST_UPDATED_TIME DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (APPLICATION_UUID) REFERENCES AM_APPLICATION(UUID) ON DELETE CASCADE,
    FOREIGN KEY (GATEWAY_ENV_ID) REFERENCES AM_GATEWAY_ENVIRONMENT(UUID),
    PRIMARY KEY (APPLICATION_UUID, GATEWAY_ENV_ID),
    UNIQUE (EXTERNAL_APP_ID, GATEWAY_ENV_ID)
);
```

---

## 2️⃣ SQL Constants

### Location
`wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.impl/src/main/java/org/wso2/carbon/apimgt/impl/dao/constants/SQLConstants.java`

### Add After API External Mapping Constants (~line 2835)

```java
// Application External Mapping SQL Statements
public static final String ADD_APPLICATION_EXTERNAL_MAPPING_SQL = "INSERT INTO AM_APPLICATION_EXTERNAL_MAPPING " +
        "(APPLICATION_UUID, GATEWAY_ENV_ID, EXTERNAL_APP_ID, REFERENCE_ARTIFACT) VALUES (?, ?, ?, ?)";

public static final String UPDATE_APPLICATION_EXTERNAL_MAPPING_SQL = "UPDATE AM_APPLICATION_EXTERNAL_MAPPING " +
        "SET REFERENCE_ARTIFACT = ?, LAST_UPDATED_TIME = ? WHERE APPLICATION_UUID = ? AND GATEWAY_ENV_ID = ?";

public static final String GET_APPLICATION_EXTERNAL_MAPPING_SQL = "SELECT REFERENCE_ARTIFACT FROM " +
        "AM_APPLICATION_EXTERNAL_MAPPING WHERE APPLICATION_UUID = ? AND GATEWAY_ENV_ID = ?";

public static final String DELETE_APPLICATION_EXTERNAL_MAPPING_SQL = "DELETE FROM AM_APPLICATION_EXTERNAL_MAPPING " +
        "WHERE APPLICATION_UUID = ? AND GATEWAY_ENV_ID = ?";

public static final String DELETE_APPLICATION_EXTERNAL_MAPPINGS_SQL = "DELETE FROM AM_APPLICATION_EXTERNAL_MAPPING " +
        "WHERE APPLICATION_UUID = ?";

public static final String GET_APPLICATION_EXTERNAL_MAPPINGS_SQL = "SELECT GATEWAY_ENV_ID, EXTERNAL_APP_ID, " +
        "REFERENCE_ARTIFACT, CREATED_TIME, LAST_UPDATED_TIME FROM AM_APPLICATION_EXTERNAL_MAPPING WHERE " +
        "APPLICATION_UUID = ?";

public static final String GET_APPLICATION_BY_EXTERNAL_APP_ID_SQL = "SELECT APPLICATION_UUID FROM " +
        "AM_APPLICATION_EXTERNAL_MAPPING WHERE EXTERNAL_APP_ID = ? AND GATEWAY_ENV_ID = ?";
```

---

## 3️⃣ DAO Methods

### Location
`wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.impl/src/main/java/org/wso2/carbon/apimgt/impl/dao/ApiMgtDAO.java`

### Add After API External Mapping Methods (~line 16300)

```java
/**
 * Add external application mapping
 *
 * @param applicationUuid UUID of the application
 * @param environmentId   Gateway environment ID
 * @param externalAppId   External application ID
 * @param referenceArtifact Reference artifact JSON
 * @throws APIManagementException if an error occurs
 */
public void addApplicationExternalMapping(String applicationUuid, String environmentId, String externalAppId,
                                           String referenceArtifact) throws APIManagementException {
    try (Connection connection = APIMgtDBUtil.getConnection();
         PreparedStatement ps = connection.prepareStatement(SQLConstants.ADD_APPLICATION_EXTERNAL_MAPPING_SQL)) {
        
        connection.setAutoCommit(false);
        ps.setString(1, applicationUuid);
        ps.setString(2, environmentId);
        ps.setString(3, externalAppId);
        ps.setBytes(4, referenceArtifact.getBytes(StandardCharsets.UTF_8));
        ps.executeUpdate();
        connection.commit();
        
    } catch (SQLException e) {
        handleException("Error while adding application external mapping for application: " + applicationUuid, e);
    }
}

/**
 * Get external application mapping reference artifact
 *
 * @param applicationUuid UUID of the application
 * @param environmentId   Gateway environment ID
 * @return Reference artifact JSON or null if not found
 * @throws APIManagementException if an error occurs
 */
public String getApplicationExternalMappingReference(String applicationUuid, String environmentId) 
        throws APIManagementException {
    String referenceArtifact = null;
    
    try (Connection connection = APIMgtDBUtil.getConnection();
         PreparedStatement ps = connection.prepareStatement(SQLConstants.GET_APPLICATION_EXTERNAL_MAPPING_SQL)) {
        
        ps.setString(1, applicationUuid);
        ps.setString(2, environmentId);
        
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                try (InputStream artifact = rs.getBinaryStream("REFERENCE_ARTIFACT")) {
                    if (artifact != null) {
                        referenceArtifact = IOUtils.toString(artifact, StandardCharsets.UTF_8);
                    }
                }
            }
        }
    } catch (SQLException | IOException e) {
        handleException("Error while retrieving application external mapping for application: " + applicationUuid, e);
    }
    
    return referenceArtifact;
}

/**
 * Update external application mapping
 *
 * @param applicationUuid UUID of the application
 * @param environmentId   Gateway environment ID
 * @param referenceArtifact Updated reference artifact JSON
 * @throws APIManagementException if an error occurs
 */
public void updateApplicationExternalMapping(String applicationUuid, String environmentId, 
                                               String referenceArtifact) throws APIManagementException {
    try (Connection connection = APIMgtDBUtil.getConnection();
         PreparedStatement ps = connection.prepareStatement(SQLConstants.UPDATE_APPLICATION_EXTERNAL_MAPPING_SQL)) {
        
        connection.setAutoCommit(false);
        ps.setBytes(1, referenceArtifact.getBytes(StandardCharsets.UTF_8));
        ps.setTimestamp(2, new Timestamp(System.currentTimeMillis()));
        ps.setString(3, applicationUuid);
        ps.setString(4, environmentId);
        ps.executeUpdate();
        connection.commit();
        
    } catch (SQLException e) {
        handleException("Error while updating application external mapping for application: " + applicationUuid, e);
    }
}

/**
 * Delete external application mapping for specific environment
 *
 * @param applicationUuid UUID of the application
 * @param environmentId   Gateway environment ID
 * @throws APIManagementException if an error occurs
 */
public void deleteApplicationExternalMapping(String applicationUuid, String environmentId) 
        throws APIManagementException {
    try (Connection connection = APIMgtDBUtil.getConnection();
         PreparedStatement ps = connection.prepareStatement(SQLConstants.DELETE_APPLICATION_EXTERNAL_MAPPING_SQL)) {
        
        connection.setAutoCommit(false);
        ps.setString(1, applicationUuid);
        ps.setString(2, environmentId);
        ps.executeUpdate();
        connection.commit();
        
    } catch (SQLException e) {
        handleException("Error while deleting application external mapping for application: " + applicationUuid, e);
    }
}

/**
 * Get all external application mappings for an application
 *
 * @param applicationUuid UUID of the application
 * @return Map of environment ID to ApplicationExternalMapping objects
 * @throws APIManagementException if an error occurs
 */
public Map<String, ApplicationExternalMapping> getApplicationExternalMappings(String applicationUuid) 
        throws APIManagementException {
    Map<String, ApplicationExternalMapping> mappings = new HashMap<>();
    
    try (Connection connection = APIMgtDBUtil.getConnection();
         PreparedStatement ps = connection.prepareStatement(SQLConstants.GET_APPLICATION_EXTERNAL_MAPPINGS_SQL)) {
        
        ps.setString(1, applicationUuid);
        
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                ApplicationExternalMapping mapping = new ApplicationExternalMapping();
                mapping.setApplicationUuid(applicationUuid);
                mapping.setGatewayEnvironmentId(rs.getString("GATEWAY_ENV_ID"));
                mapping.setExternalApplicationId(rs.getString("EXTERNAL_APP_ID"));
                
                try (InputStream artifact = rs.getBinaryStream("REFERENCE_ARTIFACT")) {
                    if (artifact != null) {
                        mapping.setReferenceArtifact(IOUtils.toString(artifact, StandardCharsets.UTF_8));
                    }
                }
                
                mapping.setCreatedTime(rs.getTimestamp("CREATED_TIME"));
                mapping.setLastUpdatedTime(rs.getTimestamp("LAST_UPDATED_TIME"));
                
                mappings.put(mapping.getGatewayEnvironmentId(), mapping);
            }
        }
    } catch (SQLException | IOException e) {
        handleException("Error while retrieving application external mappings for application: " + applicationUuid, e);
    }
    
    return mappings;
}

/**
 * Get application UUID by external application ID
 *
 * @param externalAppId External application ID
 * @param environmentId Gateway environment ID
 * @return Application UUID or null if not found
 * @throws APIManagementException if an error occurs
 */
public String getApplicationUuidByExternalAppId(String externalAppId, String environmentId) 
        throws APIManagementException {
    String applicationUuid = null;
    
    try (Connection connection = APIMgtDBUtil.getConnection();
         PreparedStatement ps = connection.prepareStatement(SQLConstants.GET_APPLICATION_BY_EXTERNAL_APP_ID_SQL)) {
        
        ps.setString(1, externalAppId);
        ps.setString(2, environmentId);
        
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                applicationUuid = rs.getString("APPLICATION_UUID");
            }
        }
    } catch (SQLException e) {
        handleException("Error while retrieving application by external ID: " + externalAppId, e);
    }
    
    return applicationUuid;
}
```

### Required Imports
```java
import org.apache.commons.io.IOUtils;
import java.io.InputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import org.wso2.carbon.apimgt.api.model.ApplicationExternalMapping;
```

---

## 4️⃣ REST API Specification

### Location
`wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.rest.api.store.v1/src/main/resources/store-api.yaml`

### Add After /applications Endpoints

```yaml
  /environments/{environmentId}/discovered-applications:
    get:
      tags:
        - Applications
      summary: Get discovered applications from external gateway
      description: |
        This operation can be used to retrieve applications discovered from an external gateway environment.
      operationId: getDiscoveredApplications
      parameters:
        - $ref: '#/components/parameters/environmentId'
        - $ref: '#/components/parameters/limit'
        - $ref: '#/components/parameters/offset'
        - name: query
          in: query
          description: |
            **Search condition**.
            You can search by application name.
          schema:
            type: string
      responses:
        '200':
          description: |
            OK.
            Discovered applications returned.
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/DiscoveredApplicationList'
        '400':
          $ref: '#/components/responses/BadRequest'
        '404':
          $ref: '#/components/responses/NotFound'
        '500':
          $ref: '#/components/responses/InternalServerError'
      security:
        - OAuth2Security:
            - apim:subscribe

  /discovered-applications/import:
    post:
      tags:
        - Applications
      summary: Import discovered application
      description: |
        This operation can be used to import a discovered application from an external gateway.
      operationId: importDiscoveredApplication
      requestBody:
        description: Application import request
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/ApplicationImportRequest'
        required: true
      responses:
        '201':
          description: |
            Created.
            Application successfully imported.
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Application'
        '400':
          $ref: '#/components/responses/BadRequest'
        '409':
          $ref: '#/components/responses/Conflict'
        '500':
          $ref: '#/components/responses/InternalServerError'
      security:
        - OAuth2Security:
            - apim:subscribe

components:
  parameters:
    environmentId:
      name: environmentId
      in: path
      description: UUID of the gateway environment
      required: true
      schema:
        type: string

  schemas:
    DiscoveredApplicationList:
      type: object
      properties:
        count:
          type: integer
          description: Number of applications returned
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
          description: External application ID in the gateway
        name:
          type: string
          description: Application name
        description:
          type: string
          description: Application description
        throttlingTier:
          type: string
          description: Throttling tier
        owner:
          type: string
          description: Application owner
        createdTime:
          type: string
          description: Application created time
        attributes:
          type: object
          additionalProperties:
            type: string
          description: Custom attributes
        keyInfo:
          type: array
          items:
            $ref: '#/components/schemas/DiscoveredApplicationKeyInfo'
        alreadyImported:
          type: boolean
          description: Whether application is already imported
        importedApplicationId:
          type: string
          description: UUID of imported application if already imported
        referenceArtifact:
          type: string
          description: Reference artifact JSON for import

    DiscoveredApplicationKeyInfo:
      type: object
      properties:
        keyType:
          type: string
          description: Key type (PRODUCTION, SANDBOX)
        keyName:
          type: string
          description: Key name
        maskedKeyValue:
          type: string
          description: Masked key value for display
        externalKeyReference:
          type: string
          description: External reference to fetch full key
        createdTime:
          type: string
          description: Key created time
        expiryTime:
          type: string
          description: Key expiry time
        state:
          type: string
          description: Key state

    ApplicationImportRequest:
      type: object
      required:
        - environmentId
        - referenceArtifact
      properties:
        environmentId:
          type: string
          description: Gateway environment ID
        referenceArtifact:
          type: string
          description: Reference artifact from DiscoveredApplication
        applicationName:
          type: string
          description: Optional custom name for imported application
```

---

## 5️⃣ Next Files to Create

1. **DTOs** (Auto-generated from OpenAPI, but you may need to tweak)
   - DiscoveredApplicationDTO
   - DiscoveredApplicationListDTO
   - DiscoveredApplicationKeyInfoDTO
   - ApplicationImportRequestDTO

2. **MappingUtil**
   - Location: `org.wso2.carbon.apimgt.rest.api.store.v1.mappings.DiscoveredApplicationMappingUtil`

3. **Service Implementation**
   - Location: `org.wso2.carbon.apimgt.rest.api.store.v1.impl.ApplicationsApiServiceImpl`
   - Methods: `getDiscoveredApplications()`, `importDiscoveredApplication()`

4. **Factory**
   - Location: `org.wso2.carbon.apimgt.impl.federated.gateway.FederatedApplicationDiscoveryFactory`

---

## 🧪 Testing Checklist

- [ ] SQL scripts execute without errors on all databases
- [ ] DAO methods can create/read/update/delete mappings
- [ ] REST API endpoints return proper responses
- [ ] Azure connector discovers applications correctly
- [ ] Import flow creates both Application and ExternalMapping
- [ ] REFERENCE_ARTIFACT JSON is stored/retrieved correctly
- [ ] Keys are properly masked in discovery responses
- [ ] Pagination works correctly
- [ ] Already-imported apps are marked correctly
- [ ] Security: No secrets exposed in API responses

---

## 📞 Need Help?

Refer to existing implementations:
- **API External Mapping**: Search for `addApiExternalApiMapping` in ApiMgtDAO.java
- **Application CRUD**: Search for `addApplication` in ApiMgtDAO.java
- **REST API Patterns**: Look at existing `/applications` endpoints in store-api.yaml
- **DTO Mapping**: Check `ApplicationMappingUtil.java` for patterns

