# Universal API Gateway - Consumer Strategy Implementation Plan

## Document Version
- **Created:** January 28, 2026
- **Status:** Planning Phase
- **Scope:** AWS, Azure, Kong, Envoy, Kubernetes Gateway

---

## Executive Summary

### Vision
Build a **Universal Developer Portal** where developers interact with a unified API consumption experience regardless of the underlying gateway technology. Developers see:
- "Subscribe to API" → Get a credential
- "View Instructions" → See how to invoke
- The gateway-specific details only surface at invocation time

### Key Principles (The "Universal Control Plane" Model)

#### ✅ Adopted Concepts
1. **Universal Developer Portal Mindset** - Design as a brand-new product with no vendor-specific concepts visible to developers
2. **Common Abstractions over Vendor Specifics** - Research all gateways to find the Lowest Common Denominator (Opaque API Keys)
3. **Flexible Credential Sourcing** - "Respect Native Generation": Gateway generates, WSO2 orchestrates and displays
4. **Per-API-Subscription Credentials** - Each subscription gets its own unique credential
5. **Heterogeneous Response Handling** - Display raw instructions when data doesn't fit the standard model

#### 🛑 Discarded Concepts
1. ~~Strict WSO2 Subscription Enforcement~~ - Can't edit other gateways to honor WSO2's logic
2. ~~Single Token Everywhere~~ - Gateways have fundamentally different security models
3. ~~WSO2 as Sole Key Generator~~ - Some gateways (AWS, Azure) generate their own keys
4. ~~Discovery as Prerequisite~~ - Users with existing subscriptions shouldn't need to "discover" them
5. ~~Vendor-Specific Terminology~~ - Architecture must use generic abstractions

---

## Part 1: Gateway Consumer Research

### 1.1 AWS API Gateway

#### Consumer Entities & Hierarchy
```
AWS Account
└── Region
    └── API Gateway REST API
        └── Stage (prod, dev)
            └── Usage Plan ← Throttling rules, quota
                └── API Key ← Opaque credential
```

#### Security/Authentication Options
| Method | How It Works | WSO2 Compatibility |
|--------|--------------|-------------------|
| **API Key** | `x-api-key` header, validated against Usage Plan | ✅ Primary choice |
| **IAM Authorization** | AWS Signature v4, requires AWS credentials | ❌ Not for external developers |
| **Lambda Authorizer** | Custom function validates token/key | ⚠️ Complex, requires custom code |
| **Cognito User Pools** | JWT from Cognito, validated by API GW | ⚠️ AWS-specific identity provider |

#### Key Limits
| Resource | Limit | Impact on Design |
|----------|-------|------------------|
| Usage Plans | 300 per region | Cannot create per-subscription |
| API Keys | 10,000 per account | Safe for per-subscription |
| APIs per Usage Plan | 300 | Sufficient for per-API model |
| Rate limit | 10,000 req/sec burst | Configurable per Usage Plan |

#### Credential Lifecycle
| Action | API Operation | Notes |
|--------|--------------|-------|
| Create API Key | `create_api_key()` | Returns key value once |
| Attach to Usage Plan | `create_usage_plan_key()` | Associates key with plan |
| Get Key Value | ❌ Cannot retrieve | Only visible at creation |
| Regenerate | Delete + Create new | Old key immediately invalid |
| Delete | `delete_api_key()` | Removes from all plans |

#### Invocation Pattern
```bash
curl -X GET \
  -H "x-api-key: YOUR_API_KEY" \
  "https://{api-id}.execute-api.{region}.amazonaws.com/{stage}/{path}"
```

#### WSO2 Entity Mapping
| WSO2 Concept | AWS Entity | Granularity |
|--------------|-----------|-------------|
| Organization | AWS Account + Region | 1:1 |
| API | REST API + Stage | 1:1 |
| Subscription Tier | Usage Plan | Per-API |
| Application | (none - just key holder) | N/A |
| Subscription | API Key | Per-subscription |

---

### 1.2 Azure API Management

#### Consumer Entities & Hierarchy
```
Azure Subscription
└── Resource Group
    └── API Management Service
        ├── Users ← Developer identity
        ├── Groups ← Role-based access
        ├── Products ← API bundles + policies
        │   └── APIs ← Individual APIs
        └── Subscriptions ← User + Product/API binding
            └── Primary/Secondary Keys ← Credentials
```

#### Security/Authentication Options
| Method | How It Works | WSO2 Compatibility |
|--------|--------------|-------------------|
| **Subscription Key** | `Ocp-Apim-Subscription-Key` header | ✅ Primary choice |
| **OAuth 2.0** | JWT validation via policy | ⚠️ Requires policy config per API |
| **Client Certificate** | mTLS authentication | ⚠️ Complex key management |
| **Basic Auth** | Username/password | ❌ Legacy, not recommended |

#### Key Limits
| Resource | Limit | Impact on Design |
|----------|-------|------------------|
| Subscriptions | Unlimited (soft limit ~100K) | Safe for per-subscription |
| Products | 400 per service | Sufficient |
| APIs per Product | 100 | May need multiple products |
| Users | Unlimited | Safe for per-application |

#### Credential Lifecycle
| Action | API Operation | Notes |
|--------|--------------|-------|
| Create Subscription | `subscriptions.create_or_update()` | Generates Primary + Secondary |
| Get Keys | `subscriptions.list_secrets()` | Can retrieve anytime |
| Regenerate Primary | `subscriptions.regenerate_primary_key()` | Secondary still works |
| Regenerate Secondary | `subscriptions.regenerate_secondary_key()` | Primary still works |
| Revoke | `subscriptions.delete()` | Both keys invalid |

#### Invocation Pattern
```bash
curl -X GET \
  -H "Ocp-Apim-Subscription-Key: YOUR_KEY" \
  "https://{service-name}.azure-api.net/{api-path}"

# OR in query string (less secure)
curl "https://{service}.azure-api.net/{path}?subscription-key=YOUR_KEY"
```

#### WSO2 Entity Mapping
| WSO2 Concept | Azure Entity | Granularity |
|--------------|-------------|-------------|
| Organization | APIM Service + Resource Group | 1:1 |
| API | API | 1:1 |
| Subscription Tier | Product (with policies) | Per-API or grouped |
| Application | User | Per-application |
| Subscription | Subscription | Per-subscription |

---

### 1.3 Kong Gateway

#### Consumer Entities & Hierarchy
```
Kong Gateway (Kubernetes or DB-backed)
├── Services ← Backend definitions
├── Routes ← URL patterns → Services
├── Consumers ← API client identity
│   ├── Credentials (key-auth, jwt, oauth2, etc.)
│   └── ACL Groups ← Access control lists
└── Plugins ← Security, rate-limiting, etc.
    ├── Global plugins
    ├── Service plugins
    ├── Route plugins
    └── Consumer plugins
```

#### Security/Authentication Options
| Method | Plugin | WSO2 Compatibility |
|--------|--------|-------------------|
| **API Key (key-auth)** | `key-auth` | ✅ Primary choice |
| **JWT** | `jwt` | ⚠️ Works with Consumer mapping |
| **OAuth 2.0** | `oauth2` | ⚠️ Kong as auth server |
| **Basic Auth** | `basic-auth` | ⚠️ Simple but less secure |
| **HMAC** | `hmac-auth` | ❌ Complex for developers |
| **LDAP** | `ldap-auth` | ❌ Enterprise internal only |

#### Key Limits
| Resource | Limit | Impact on Design |
|----------|-------|------------------|
| Consumers | Unlimited | Safe |
| Credentials per Consumer | Unlimited | Safe |
| Plugins | Unlimited | Safe |
| Routes | Unlimited | Safe |

#### Credential Lifecycle
| Action | API/K8s Operation | Notes |
|--------|------------------|-------|
| Create Consumer | `KongConsumer` CR or Admin API | Named entity |
| Create Key | `Secret` with `key-auth` credential | Can set key value |
| Create ACL | `Secret` with `acl` credential | Group membership |
| Get Key | Read Secret | Full value retrievable |
| Regenerate | Delete + Create credential | New key value |
| Revoke | Delete credential Secret | Immediate |

#### Invocation Pattern
```bash
# API Key in header
curl -X GET \
  -H "apikey: YOUR_API_KEY" \
  "https://{kong-proxy}/{route-path}"

# Or in query param
curl "https://{kong-proxy}/{path}?apikey=YOUR_KEY"

# JWT token
curl -X GET \
  -H "Authorization: Bearer YOUR_JWT" \
  "https://{kong-proxy}/{route-path}"
```

#### WSO2 Entity Mapping
| WSO2 Concept | Kong Entity | Granularity |
|--------------|------------|-------------|
| Organization | Namespace / Tags | 1:1 |
| API | Service + Route | 1:1 |
| Subscription Tier | Rate-limiting Plugin | Per-API/Consumer |
| Application | Consumer | Per-application |
| Subscription | Key-auth credential + ACL | Per-subscription |

---

### 1.4 Envoy Gateway

#### Consumer Entities & Hierarchy
```
Kubernetes Cluster
└── Namespace (org/tenant boundary)
    └── Gateway (Envoy Gateway CR)
        └── HTTPRoute (K8s Gateway API)
            ├── SecurityPolicy ← Auth rules
            │   ├── API Key validation
            │   ├── JWT validation
            │   └── External auth
            ├── BackendTrafficPolicy ← Backend config
            └── Service ← Backend endpoint
                
Secrets (for credentials):
└── API Key secrets
└── Basic auth secrets
└── TLS certificates
```

#### Security/Authentication Options
| Method | Implementation | WSO2 Compatibility |
|--------|---------------|-------------------|
| **API Key** | SecurityPolicy + ext_authz or header match | ✅ Primary choice |
| **JWT** | SecurityPolicy with JWT provider | ⚠️ Needs claim-to-permission mapping |
| **Basic Auth** | SecurityPolicy + ext_authz | ⚠️ Simple but requires authz service |
| **mTLS** | BackendTLSPolicy | ⚠️ Certificate management complex |
| **External Auth** | ext_authz filter | ⚠️ Adds latency |

#### Key Limits
| Resource | Limit | Impact on Design |
|----------|-------|------------------|
| Secrets | 1M per cluster (K8s limit) | Safe |
| HTTPRoutes | Unlimited | Safe |
| SecurityPolicies | Unlimited | Safe |

#### Credential Lifecycle
| Action | K8s Operation | Notes |
|--------|--------------|-------|
| Create Credential | Create Secret | WSO2 generates key value |
| Store in Policy | Reference Secret in SecurityPolicy | Links to route |
| Get Key | Read Secret | Full value in K8s |
| Regenerate | Update Secret data | Rolling update possible |
| Revoke | Delete Secret | Immediate |

#### Invocation Pattern
```bash
# API Key in header (configurable header name)
curl -X GET \
  -H "x-api-key: YOUR_API_KEY" \
  "https://{gateway-host}/{route-path}"

# Basic Auth
curl -X GET \
  -u "username:password" \
  "https://{gateway-host}/{route-path}"
```

#### WSO2 Entity Mapping
| WSO2 Concept | Envoy/K8s Entity | Granularity |
|--------------|-----------------|-------------|
| Organization | Namespace | 1:1 |
| API | HTTPRoute + Service | 1:1 |
| Subscription Tier | BackendTrafficPolicy (rate limit) | Per-API |
| Application | (label on secrets) | Metadata only |
| Subscription | Secret + SecurityPolicy reference | Per-subscription |

---

### 1.5 Kubernetes Gateway API (Native)

#### Note
Kubernetes Gateway API is a **specification**, not a runtime. It requires a **Gateway Controller** (Envoy Gateway, Kong, Traefik, etc.).

For this plan:
- **Envoy Gateway** is the reference implementation
- Patterns apply to other controllers with minor variations

#### Consumer Entities (K8s Gateway API Standard)
```
GatewayClass ← Controller type (e.g., EnvoyProxy, Kong)
Gateway ← Entry point (listeners, TLS)
HTTPRoute ← Routing rules
GRPCRoute ← gRPC routing
ReferenceGrant ← Cross-namespace access
```

**No native consumer/credential model** - Relies on controller-specific extensions:
- Envoy: SecurityPolicy
- Kong: KongConsumer + KongPlugin
- Traefik: Middleware

#### Authentication Options (Controller Dependent)
| Controller | Supported Auth | Notes |
|-----------|---------------|-------|
| Envoy Gateway | API Key, JWT, Basic, mTLS | Via SecurityPolicy |
| Kong | All key-auth, jwt, oauth2, etc. | Via KongPlugin |
| Traefik | Basic, Forward Auth, API Key | Via Middleware |
| Contour | mTLS, ext_authz | Limited options |

---

## Part 2: Universal Abstraction Layer Design

### 2.1 Common Concepts

Based on the research, here are the **Lowest Common Denominators**:

| Universal Concept | Description | Gateway Mappings |
|------------------|-------------|------------------|
| **API** | A published, discoverable API | AWS API, Azure API, Kong Route, K8s HTTPRoute |
| **Application** | Developer's container for subscriptions | AWS (none), Azure User, Kong Consumer, K8s (label) |
| **Subscription** | Link between Application and API | AWS API Key, Azure Subscription, Kong key-auth, K8s Secret |
| **Credential** | The actual key/token | API Key (all gateways) |
| **Invocation Instruction** | How to call the API | Header name + URL pattern (varies) |

### 2.2 Identifier Pattern

**Pattern:** `wso2_{org}_{appUuid}_{apiUuid}_{env}`

**Example:**
- Org: `acme`
- App UUID: `a1b2c3d4`
- API UUID: `e5f6g7h8`
- Env: `prod`

**Result:** `wso2_acme_a1b2c3d4_e5f6g7h8_prod`

**Gateway-Specific Application:**

| Gateway | Entity | Naming Pattern | Character Limits |
|---------|--------|---------------|------------------|
| AWS | API Key name | `wso2_acme_a1b2_e5f6_prod` | 256 chars |
| Azure | Subscription displayName | `wso2_acme_a1b2_e5f6_prod` | 100 chars |
| Kong | Consumer username | `wso2-acme-a1b2-e5f6-prod` | No limit (use hyphens) |
| Envoy | Secret name | `wso2-acme-a1b2-e5f6-prod` | 253 chars (K8s limit) |

### 2.3 Entity Granularity Matrix

| Gateway | Container Entity | Level | Credential Entity | Level | Rationale |
|---------|-----------------|-------|-------------------|-------|-----------|
| **AWS** | Usage Plan | Per-API | API Key | Per-subscription | Avoids 300 plan limit |
| **Azure** | User | Per-Application | Subscription | Per-subscription | Natural Azure model |
| **Kong** | Consumer | Per-Application | key-auth Secret | Per-subscription | Reuse consumer |
| **Envoy** | SecurityPolicy | Per-API | Secret | Per-subscription | Policy controls access |
| **K8s GW** | (same as controller) | - | - | - | - |

### 2.4 Credential Generation Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Developer Action                         │
│                "Subscribe to Weather API"                   │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              Universal Subscription Service                  │
│  1. Validate API exists                                     │
│  2. Check application ownership                             │
│  3. Determine gateway type for this API                     │
│  4. Delegate to Gateway Agent                               │
└──────────────────────────┬──────────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          │                │                │
          ▼                ▼                ▼
   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
   │  AWS Agent  │  │ Azure Agent │  │ Kong Agent  │
   └──────┬──────┘  └──────┬──────┘  └──────┬──────┘
          │                │                │
          ▼                ▼                ▼
   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
   │ 1. Check/   │  │ 1. Check/   │  │ 1. Check/   │
   │    Create   │  │    Create   │  │    Create   │
   │    Usage    │  │    User     │  │    Consumer │
   │    Plan     │  │             │  │             │
   │ 2. Create   │  │ 2. Create   │  │ 2. Create   │
   │    API Key  │  │    Sub-     │  │    key-auth │
   │ 3. Attach   │  │    scription│  │ 3. Create   │
   │    to Plan  │  │ 3. Get Keys │  │    ACL      │
   │ 4. Return   │  │ 4. Return   │  │ 4. Return   │
   │    Key      │  │    Key      │  │    Key      │
   └──────┬──────┘  └──────┬──────┘  └──────┬──────┘
          │                │                │
          └────────────────┼────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              Universal Subscription Service                  │
│  1. Store credential reference (masked) in WSO2 DB          │
│  2. Store external entity IDs for management                │
│  3. Return credential + invocation instructions             │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   Developer Portal UI                        │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Weather API - Subscription Created ✓               │    │
│  │                                                     │    │
│  │ API Key: ••••••••••••ab12           [Copy] [Show]  │    │
│  │                                                     │    │
│  │ How to Invoke:                                      │    │
│  │ ────────────────                                    │    │
│  │ Header: x-api-key                                   │    │
│  │ URL: https://abc123.execute-api.us-east-1...       │    │
│  │                                                     │    │
│  │ [Try in API Console]                               │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

---

## Part 3: Supported Actions

### 3.1 Developer Actions (v1 Scope)

| Action | Description | Triggers |
|--------|-------------|----------|
| **Subscribe** | Create subscription to an API | Container + Credential creation |
| **Unsubscribe** | Remove subscription | Credential deletion |
| **Regenerate Key** | Get new key, old invalidated | Delete + Create credential |
| **List Subscriptions** | View all subscriptions in app | Read-only query |
| **View Instructions** | See how to invoke API | Read-only, gateway-specific |

### 3.2 Action Implementation Matrix

| Action | AWS | Azure | Kong | Envoy |
|--------|-----|-------|------|-------|
| **Subscribe** | | | | |
| - Container check/create | Check/Create Usage Plan | Check/Create User | Check/Create Consumer | Check/Create SecurityPolicy |
| - Credential create | `create_api_key()` + attach | `create_subscription()` | Create key-auth Secret | Create API Key Secret |
| - ACL/Access control | Key → Usage Plan | Subscription → API scope | Create ACL credential | Update SecurityPolicy |
| **Unsubscribe** | | | | |
| - Credential delete | `delete_api_key()` | `delete_subscription()` | Delete key-auth Secret | Delete Secret |
| - ACL cleanup | Auto (key gone) | Auto (sub gone) | Delete ACL credential | Update SecurityPolicy |
| - Container cleanup | Never (reused) | Never (User reused) | Never (Consumer reused) | Check if policy empty |
| **Regenerate** | | | | |
| - Old key handling | Delete old key | N/A (regenerate in place) | Delete old Secret | Update Secret data |
| - New key creation | Create new key + attach | `regenerate_primary_key()` | Create new Secret | Generate new value |
| - Return new key | From create response | From `list_secrets()` | From Secret | From Secret |
| **List Subscriptions** | | | | |
| - Query method | List keys, filter by app tag | List subs by user | List credentials by consumer | List Secrets by label |
| **View Instructions** | | | | |
| - Header name | `x-api-key` | `Ocp-Apim-Subscription-Key` | `apikey` | `x-api-key` |
| - URL pattern | `{api-id}.execute-api.{region}.amazonaws.com/{stage}/{path}` | `{service}.azure-api.net/{path}` | `{kong-proxy}/{route}` | `{gateway}/{path}` |

### 3.3 Out of Scope (v1)

| Feature | Reason Deferred |
|---------|-----------------|
| OAuth2/JWT authentication | Requires KeyManager federation, lookup tables |
| Key rotation with grace period | Added complexity, regenerate sufficient for v1 |
| Application-level rate limiting | Developer doesn't need self-throttling, federation handles API tiers |
| Admin subscription management | Admin portal scope, not developer portal |
| Usage analytics per subscription | Requires gateway-specific metrics integration |
| Multi-key per subscription | Complexity, Azure model is exception |

---

## Part 4: Invocation Instructions

### 4.1 Instruction Data Model

```typescript
interface InvocationInstruction {
  // Universal fields
  gatewayType: "aws" | "azure" | "kong" | "envoy" | "kubernetes";
  apiName: string;
  apiVersion: string;
  
  // Credential info
  credentialType: "api-key";
  credentialHeaderName: string;      // e.g., "x-api-key", "Ocp-Apim-Subscription-Key"
  credentialQueryParam?: string;     // e.g., "subscription-key" (Azure alternative)
  credentialValue: string;           // Masked or full based on context
  
  // Endpoint info
  baseUrl: string;                   // e.g., "https://abc123.execute-api.us-east-1.amazonaws.com"
  basePath: string;                  // e.g., "/prod/weather"
  fullUrl: string;                   // Combined for convenience
  
  // Additional context
  region?: string;                   // AWS region
  environment: "production" | "sandbox";
  
  // Example curl command (pre-generated)
  curlExample: string;
}
```

### 4.2 Gateway-Specific Patterns

| Gateway | Header Name | URL Pattern | Example |
|---------|-------------|-------------|---------|
| AWS | `x-api-key` | `https://{api-id}.execute-api.{region}.amazonaws.com/{stage}/{path}` | `https://abc123.execute-api.us-east-1.amazonaws.com/prod/weather` |
| Azure | `Ocp-Apim-Subscription-Key` | `https://{service}.azure-api.net/{api-base-path}` | `https://acme-apim.azure-api.net/weather/v1` |
| Kong | `apikey` | `https://{kong-proxy}/{route-path}` | `https://kong.acme.com/weather` |
| Envoy | `x-api-key` (configurable) | `https://{gateway-host}/{route-path}` | `https://gateway.acme.com/weather` |

---

## Part 5: Database Schema Considerations

### 5.1 Existing Tables (Reference)

```sql
-- Already exists from Application Federation work
CREATE TABLE AM_APPLICATION_EXTERNAL_MAPPING (
    APPLICATION_UUID VARCHAR(256) NOT NULL,
    GATEWAY_ENV_ID VARCHAR(255) NOT NULL,
    EXTERNAL_APP_ID VARCHAR(512) NOT NULL,
    REFERENCE_ARTIFACT LONGBLOB NOT NULL,
    CREATED_TIME TIMESTAMP,
    LAST_UPDATED_TIME TIMESTAMP,
    PRIMARY KEY (APPLICATION_UUID, GATEWAY_ENV_ID)
);
```

### 5.2 New Table: AM_SUBSCRIPTION_EXTERNAL_MAPPING

```sql
-- New table for subscription-level mapping
CREATE TABLE AM_SUBSCRIPTION_EXTERNAL_MAPPING (
                                                SUBSCRIPTION_UUID VARCHAR(256) NOT NULL,
                                                GATEWAY_ENV_ID VARCHAR(255) NOT NULL,
                                                EXTERNAL_SUBSCRIPTION_ID VARCHAR(512) NOT NULL,  -- Gateway-specific ID
                                                EXTERNAL_CONTAINER_ID VARCHAR(512),              -- Usage Plan, User, Consumer ID
                                                CREDENTIAL_REFERENCE VARCHAR(1024),              -- Masked key or reference
                                                INVOCATION_METADATA LONGBLOB NOT NULL,           -- JSON with header, URL, etc.
                                                CREATED_TIME TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                                                LAST_UPDATED_TIME TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                                                FOREIGN KEY (SUBSCRIPTION_UUID) REFERENCES AM_SUBSCRIPTION(UUID) ON DELETE CASCADE,
                                                FOREIGN KEY (GATEWAY_ENV_ID) REFERENCES AM_GATEWAY_ENVIRONMENT(UUID),
                                                PRIMARY KEY (SUBSCRIPTION_UUID, GATEWAY_ENV_ID),
                                                UNIQUE (EXTERNAL_SUBSCRIPTION_ID, GATEWAY_ENV_ID)
);
```

### 5.3 Invocation Metadata Schema

```json
{
  "gatewayType": "aws",
  "credentialType": "api-key",
  "headerName": "x-api-key",
  "baseUrl": "https://abc123.execute-api.us-east-1.amazonaws.com",
  "basePath": "/prod",
  "region": "us-east-1",
  "stage": "prod",
  "externalEntities": {
    "usagePlanId": "abc123",
    "apiKeyId": "xyz789"
  }
}
```

---

## Part 6: Implementation Phases

### Phase 1: Research & Design (Current)
- [x] Document gateway consumer strategies
- [x] Define entity mappings
- [x] Define identifier patterns
- [x] Define supported actions
- [x] Design database schema
- [ ] Review and finalize with stakeholders

### Phase 2: Core Abstractions
- [ ] Create universal `SubscriptionAgent` interface
- [ ] Define `InvocationInstruction` data model
- [ ] Create `CredentialReference` model
- [ ] Implement subscription external mapping DAO

### Phase 3: Gateway Agent Implementations
- [ ] **AWS Agent**
  - [ ] Usage Plan management (per-API)
  - [ ] API Key CRUD operations
  - [ ] Invocation instruction generation
- [ ] **Azure Agent**
  - [ ] User management (per-Application)
  - [ ] Subscription CRUD operations
  - [ ] Key retrieval and regeneration
- [ ] **Kong Agent**
  - [ ] Consumer management (per-Application)
  - [ ] key-auth credential operations
  - [ ] ACL management
- [ ] **Envoy Agent**
  - [ ] SecurityPolicy management
  - [ ] Secret CRUD operations
  - [ ] Policy reference updates

### Phase 4: REST API
- [ ] Define OpenAPI spec for subscription endpoints
- [ ] Implement subscription service
- [ ] Implement instruction retrieval endpoint
- [ ] Add to existing Application endpoints

### Phase 5: Developer Portal UI
- [ ] Subscription creation flow
- [ ] Instruction display component
- [ ] Key management (show/copy/regenerate)
- [ ] Swagger UI integration for testing

### Phase 6: Testing & Documentation
- [ ] Unit tests per gateway agent
- [ ] Integration tests with live gateways
- [ ] End-to-end developer flow testing
- [ ] Developer documentation

---

## Part 7: Open Questions & Risks

### Open Questions

| # | Question | Impact | Status |
|---|----------|--------|--------|
| 1 | How to handle API deployed to multiple gateways? | Subscription creates credentials on all? | To discuss |
| 2 | Should we cache credentials in WSO2 or always fetch? | Performance vs. freshness | To decide |
| 3 | How to handle gateway-side key expiration? | Azure keys don't expire, AWS can set TTL | Per-gateway logic |
| 4 | Error handling when gateway is unreachable? | Retry? Queue? Fail fast? | To design |
| 5 | How to sync if gateway-side entity is deleted? | Reconciliation job? | To design |

### Risks

| Risk | Mitigation |
|------|------------|
| Gateway API changes | Use SDK versioning, abstract gateway-specific code |
| Rate limits on gateway management APIs | Implement backoff, batch operations where possible |
| Credential exposure | Never log keys, mask in storage, HTTPS only |
| Inconsistent state (WSO2 vs. gateway) | Eventual consistency model, reconciliation jobs |
| Per-gateway quirks | Thorough testing, gateway-specific error handling |

---

## Appendix A: Gateway SDK/API References

### AWS
- SDK: `boto3` (Python) or `software.amazon.awssdk` (Java)
- Docs: https://docs.aws.amazon.com/apigateway/latest/api/

### Azure
- SDK: `azure-resourcemanager-apimanagement`
- Docs: https://docs.microsoft.com/en-us/rest/api/apimanagement/

### Kong
- Admin API: RESTful HTTP API or Kubernetes CRDs
- Docs: https://docs.konghq.com/gateway/latest/admin-api/

### Envoy Gateway
- Kubernetes CRDs (Gateway API + Envoy extensions)
- Docs: https://gateway.envoyproxy.io/

---

## Appendix B: Credential Handling Best Practices

1. **Never log credentials** - Use masked values in logs
2. **Encrypt at rest** - Use database encryption for credential references
3. **HTTPS only** - All credential transmission over TLS
4. **Short display window** - Auto-hide credentials after brief display
5. **Audit trail** - Log who accessed/regenerated credentials (without the value)
6. **Gateway-side rotation** - Encourage periodic regeneration
7. **Least privilege** - WSO2 service accounts have minimal permissions on gateways

---

## Approval & Sign-off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Architect | | | |
| Tech Lead | | | |
| Product Owner | | | |

---

*Document generated: January 28, 2026*
*Next Review: After stakeholder feedback*