****# Universal API Gateway - Consumer Strategy Implementation Plan

## Document Version
- **Created:** January 28, 2026
- **Last Updated:** January 29, 2026
- **Status:** ✅ UPDATED - Simplified Architecture (WSO2 as Control Plane)
- **Scope:** AWS, Azure, Kong, Envoy, Kubernetes Gateway

### Recent Updates (Jan 29, 2026)
- **Simplified entity model:** Application-level entities skipped on all gateways
- **Kong approach changed:** Consumer = Subscription (not Consumer = Application)
- **Azure simplified:** No User creation, standalone Subscriptions
- **Reference artifact parsing:** Moved to connector layer (separation of concerns)
- **Architecture clarified:** WSO2 = Control Plane (management), Gateways = Data Plane (runtime, no WSO2 introspection)

---

## Quick Reference: Consolidated Entity Mapping

### Entity Mapping Matrix (SIMPLIFIED - WSO2 as Control Plane)

| WSO2 Entity | AWS | Azure | Kong | Envoy/K8s GW |
|-------------|-----|-------|------|--------------|
| **Organization** | Tag prefix | APIM Service | Namespace | Namespace |
| **Application** | *(none)* | *(none)* | *(none)* | *(labels only)* |
| **API** | Usage Plan | API | Route + ACL Plugin | HTTPRoute + SecurityPolicy |
| **Subscription** | API Key | Subscription (API-scoped) | **Consumer + key-auth** | Secret |

**Key Design Decision:** WSO2 is the sole control plane for all enforcement (authorization, throttling, app ownership). Gateways are **credential providers only**. Application-level entities are skipped for all gateways - each subscription creates one gateway entity.

### What Gets Created & When (SIMPLIFIED)

| Event | AWS | Azure | Kong | Envoy |
|-------|-----|-------|------|-------|
| **API Deployed** | Create Usage Plan | *(API exists)* | Create Route, Service, ACL Plugin | Create HTTPRoute, SecurityPolicy |
| **App Created** | *(nothing)* | *(nothing)* | *(nothing)* | *(nothing)* |
| **Subscription** | Create API Key, attach to Usage Plan | Create Subscription (API-scoped, no User) | **Create Consumer + key-auth + ACL** | Generate key, create Secret, update SecurityPolicy |
| **Unsubscribe** | Delete API Key | Delete Subscription | **Delete Consumer** (cascades) | Delete Secret, update SecurityPolicy |
| **Regenerate Key** | Delete + Create API Key | Regenerate Primary Key | Delete + Create key-auth | Update Secret data |

**Key Changes from Original Design:**
- **Azure:** No User creation (Subscriptions are standalone)
- **Kong:** Consumer created per-subscription (not per-application)
- **All:** Application-level entities skipped - WSO2 enforces app ownership before subscription creation

### Key Generation Responsibility (CONFIRMED)

| Gateway | Who Generates Key? | Retrievable? |
|---------|-------------------|--------------|
| AWS | AWS generates | ❌ Only at creation time |
| Azure | Azure generates | ✅ Yes, via API |
| Kong | WSO2 can set value | ✅ Yes, from Secret |
| Envoy | WSO2 generates | ✅ Yes, from Secret |

### Identifier Pattern (UPDATED)

**Pattern:** `wso2_{subscriptionUuid}`

WSO2 subscription UUID is already unique (36 chars). Total = `wso2_` + UUID = **41 chars**, fits all gateway limits.
All context (org, app, API, env) is stored in `AM_SUBSCRIPTION_EXTERNAL_MAPPING` on the WSO2 side.

| Gateway | Entity | Example | Char Limit |
|---------|--------|---------|------------|
| AWS | API Key name | `wso2_80369180-7d90-4ee8-99a1-19fa68512aa5` | 256 |
| Azure | Subscription SID | `wso2_80369180-7d90-4ee8-99a1-19fa68512aa5` | 80 |
| Kong | Consumer name | `wso2_80369180-7d90-4ee8-99a1-19fa68512aa5` | No limit |
| Envoy | Secret name | `wso2_80369180-7d90-4ee8-99a1-19fa68512aa5` | 253 (K8s) |

### Out of Scope for v1 (CONFIRMED)

- ❌ Azure Products (tier grouping) - skipped for simplicity
- ❌ OAuth2/JWT authentication - opaque keys only
- ❌ Key rotation with grace period - regenerate only
- ❌ Application-level rate limiting - not needed now
- ❌ Externally-managed gateways (read-only brownfield) - different feature
- ❌ K8s Gateway controllers other than Envoy (Traefik, Contour) - future phase

---

## Executive Summary

### Vision
Build a **Universal Developer Portal** where developers interact with a unified API consumption experience regardless of the underlying gateway technology. Developers see:
- "Subscribe to API" → Get a credential
- "View Instructions" → See how to invoke
- The gateway-specific details only surface at invocation time

### Key Principles (The "Universal Control Plane" Model)

#### What "Universal Control Plane" Means

**WSO2 = Control Plane (Subscription Management)**
- ✅ Developer creates subscriptions in WSO2 DevPortal
- ✅ WSO2 enforces authorization (app ownership, API access policies)
- ✅ WSO2 orchestrates credential creation on external gateways
- ✅ WSO2 is the source of truth for subscription lifecycle

**Gateways = Data Plane (Runtime Traffic)**
- ✅ Runtime API invocations go **directly to gateways** (bypass WSO2)
- ✅ Gateways validate credentials locally (no WSO2 introspection)
- ✅ Gateways enforce their own rate limits and policies
- ✅ Gateways handle analytics and metrics

**Critical Trade-off:**
- ❌ WSO2 does NOT see runtime API traffic
- ❌ WSO2 cannot enforce throttling at runtime (gateways use their own limits)
- ❌ WSO2 cannot provide real-time analytics (must sync from gateways)
- ✅ WSO2 provides unified subscription management across all gateways

#### ✅ Adopted Concepts
1. **Universal Developer Portal Mindset** - Design as a brand-new product with no vendor-specific concepts visible to developers
2. **WSO2 as Subscription Orchestrator** - WSO2 manages subscription lifecycle, gateways handle runtime validation
3. **Simplified Entity Model** - Skip Application-level entities on gateways (WSO2 already enforces app ownership)
4. **Common Abstractions over Vendor Specifics** - Research all gateways to find the Lowest Common Denominator (Opaque API Keys)
5. **Flexible Credential Sourcing** - "Respect Native Generation": Gateway generates, WSO2 orchestrates and displays
6. **Per-API-Subscription Credentials** - Each subscription gets its own unique credential
7. **Connector-Owned Parsing** - Each connector parses its own reference artifact format (no gateway-specific logic in REST API layer)

#### 🛑 Discarded Concepts
1. ~~Strict WSO2 Subscription Enforcement~~ - Can't edit other gateways to honor WSO2's logic
2. ~~Single Token Everywhere~~ - Gateways have fundamentally different security models
3. ~~WSO2 as Sole Key Generator~~ - Some gateways (AWS, Azure) generate their own keys
4. ~~Discovery as Prerequisite~~ - Users with existing subscriptions shouldn't need to "discover" them
5. ~~Vendor-Specific Terminology~~ - Architecture must use generic abstractions

---

## Architecture: Control Plane vs Data Plane

### Control Plane (WSO2) - Subscription Management

**What happens when a developer subscribes:**
```
1. Developer → WSO2 DevPortal → "Subscribe to Weather API"
2. WSO2 validates:
   ✓ Does user own this application?
   ✓ Is application allowed to subscribe to this API?
   ✓ What throttling tier applies?
3. WSO2 → Calls Gateway Agent (Azure/AWS/Kong/Envoy)
4. Gateway Agent → Creates credential on external gateway
5. Gateway → Returns credential to WSO2
6. WSO2 → Stores subscription in AM_SUBSCRIPTION + AM_SUBSCRIPTION_EXTERNAL_MAPPING
7. WSO2 → Displays credential to developer (one-time)
```

**WSO2 Responsibilities (Management Time):**
- ✅ Authorization (who can subscribe)
- ✅ Application ownership enforcement
- ✅ Subscription lifecycle (create, delete, regenerate)
- ✅ Credential orchestration and display
- ✅ Unified Developer Portal experience

### Data Plane (Gateway) - Runtime Traffic

**What happens when a developer invokes the API:**
```
1. Developer → curl -H "apikey: abc123" https://gateway.example.com/weather
2. Request goes DIRECTLY to external gateway (bypasses WSO2!)
3. Gateway validates:
   ✓ Is this credential valid?
   ✓ Does it have access to this API/route?
4. Gateway → Forwards to backend API if valid
5. Backend → Returns response → Gateway → Developer
```

**Gateway Responsibilities (Runtime):**
- ✅ Credential validation
- ✅ Rate limiting (using gateway's own policies)
- ✅ Request routing and load balancing
- ✅ Analytics and metrics collection
- ✅ Response transformation

### What WSO2 Cannot Do (By Design)

Because runtime traffic bypasses WSO2:
- ❌ **No runtime introspection:** WSO2 does not see API invocation requests
- ❌ **No throttling enforcement:** WSO2 cannot enforce rate limits at runtime (gateways use their own)
- ❌ **No real-time analytics:** Invocation counts, latency, errors tracked by gateway (not WSO2)
- ❌ **No runtime policies:** Mediation, transformation, additional security checks happen on gateway

### Implications for Features

| Feature | WSO2 Role | Gateway Role |
|---------|-----------|--------------|
| **Subscription creation** | ✅ Manages | Provides credential |
| **App ownership** | ✅ Enforces at subscription time | N/A |
| **Throttling tiers** | Assigns tier name | ❌ Ignores WSO2 tiers, uses own limits |
| **Runtime validation** | N/A | ✅ Validates credentials |
| **Analytics** | ❌ No runtime visibility | ✅ Tracks all invocations |
| **Credential regeneration** | ✅ Orchestrates | Generates new credential |

**This is a trade-off:** WSO2 provides unified subscription management, but gateways handle all runtime concerns independently.

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

#### WSO2 Entity Mapping (CONFIRMED)
| WSO2 Concept | AWS Entity | When Created | Naming Pattern |
|--------------|-----------|--------------|----------------|
| Organization | Tag prefix on entities | - | `wso2_acme_` |
| Application | *(none)* | *(nothing created)* | - |
| API | Usage Plan | When API deployed | `wso2_acme_weatherAPI_prod` |
| Subscription | API Key (attached to Usage Plan) | When subscribed | `wso2_acme_app1_weatherAPI_prod` |

**Key Design Decision:** Usage Plan created **per-API** (not per-subscription) to avoid 300 plan limit. Multiple API Keys (subscriptions) attach to same Usage Plan.

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

#### WSO2 Entity Mapping (SIMPLIFIED - No Users or Products)
| WSO2 Concept | Azure Entity | When Created | Naming Pattern |
|--------------|-------------|--------------|----------------|
| Organization | APIM Service | Pre-exists | - |
| Application | *(none)* | - | - |
| API | API | When deployed | *(uses existing API)* |
| ~~Subscription Tier~~ | ~~Product~~ | **SKIPPED for v1** | - |
| Subscription | Subscription (API-scoped, standalone) | When subscribed | `wso2_{subscriptionUuid}` |

**Key Design Decisions:**
1. **No Users:** Azure Subscriptions can be standalone (no `userId` required). WSO2 already enforces app ownership before subscription creation.
2. **No Products:** Subscriptions scoped directly to APIs. Tier-based grouping deferred to future phase.
3. **Simpler lifecycle:** One entity per subscription, cleaner delete operation.

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

#### WSO2 Entity Mapping (SIMPLIFIED - Consumer = Subscription)
| WSO2 Concept | Kong Entity | When Created | Naming Pattern |
|--------------|------------|--------------|----------------|
| Organization | Namespace (K8s) | Pre-exists | - |
| Application | *(none)* | - | - |
| API | Route + Service + ACL Plugin | When deployed | ACL group: `api-weather-prod` |
| Subscription | **Consumer** (with key-auth + ACL) | When subscribed | `wso2_{subscriptionUuid}` |

**Key Design Decision:** Consumer created **per-Subscription** (not per-Application). Each subscription gets:
- One Consumer (represents the subscription)
- One key-auth credential (attached to Consumer)
- One ACL group membership (grants access to one API)

**Rationale:** Simpler lifecycle management - deleting subscription = delete Consumer (cascades to credential and ACL). Consistent with other gateways (one entity per subscription). WSO2 already enforces app ownership before subscription creation.

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

#### WSO2 Entity Mapping (CONFIRMED)
| WSO2 Concept | Envoy/K8s Entity | When Created | Naming Pattern |
|--------------|-----------------|--------------|----------------|
| Organization | Namespace | Pre-exists | `acme` |
| Application | Labels on Secrets | Metadata only | `app: mobileapp` |
| API | HTTPRoute + SecurityPolicy | When deployed | `wso2-weather-prod` |
| Subscription | Secret (API key inside) | When subscribed | `wso2-acme-mobileapp-weather-prod` |

**Key Design Decision:** Envoy has no native Consumer concept. Application is just a **label** on Secrets. WSO2 **generates keys** (Envoy doesn't). SecurityPolicy is updated to reference new Secrets when subscriptions are added.

---

### 1.5 Kubernetes Gateway API (CONFIRMED: Same as Envoy)

#### Note
Kubernetes Gateway API is a **specification**, not a runtime. It requires a **Gateway Controller** (Envoy Gateway, Kong, Traefik, etc.).

**For v1: K8s Gateway API = Envoy Gateway**

Other controllers (Traefik, Contour) deferred to future phase.

#### Consumer Entities (K8s Gateway API Standard)
```
GatewayClass ← Controller type (e.g., EnvoyProxy, Kong)
Gateway ← Entry point (listeners, TLS)
HTTPRoute ← Routing rules
GRPCRoute ← gRPC routing
ReferenceGrant ← Cross-namespace access
```

**No native consumer/credential model** - Relies on controller-specific extensions:
- Envoy: SecurityPolicy ← **We use this for v1**
- Kong: KongConsumer + KongPlugin (covered in section 1.3)
- Traefik: Middleware (out of scope for v1)

#### WSO2 Entity Mapping (CONFIRMED - Same as Envoy Gateway)

See section 1.4 for detailed Envoy Gateway mapping. The same patterns apply.

---

## Part 2: Universal Abstraction Layer Design

### 2.1 Common Concepts

Based on the research, here are the **Lowest Common Denominators**:

| Universal Concept | Description | Gateway Mappings |
|------------------|-------------|------------------|
| **API** | A published, discoverable API | AWS API, Azure API, Kong Route, K8s HTTPRoute |
| **Application** | Developer's container for subscriptions **(managed in WSO2 only)** | AWS (none), Azure (none), Kong (none), K8s (labels only) |
| **Subscription** | Link between Application and API | AWS API Key, Azure Subscription, **Kong Consumer**, K8s Secret |
| **Credential** | The actual key/token | API Key (all gateways) |
| **Invocation Instruction** | How to call the API | Header name + URL pattern (varies) |

**Note:** Application-level entities are skipped on all gateways. WSO2 enforces app ownership at subscription creation time. Each subscription creates exactly one gateway entity.

### 2.2 Identifier Pattern (UPDATED)

**Pattern:** `wso2_{subscriptionUuid}`

WSO2 subscription UUID is already unique (36 chars). Total = `wso2_` + UUID = **41 chars**.
All context (org, app, API, env) is stored in `AM_SUBSCRIPTION_EXTERNAL_MAPPING` on the WSO2 side — no need to encode it in the external name.

**Example:**
- Subscription UUID: `80369180-7d90-4ee8-99a1-19fa68512aa5`
- **Result:** `wso2_80369180-7d90-4ee8-99a1-19fa68512aa5` (41 chars)

**Gateway-Specific Application:**

| Gateway | Entity | Naming Pattern | Character Limits |
|---------|--------|---------------|------------------|
| AWS | API Key name | `wso2_{subscriptionUuid}` | 256 chars |
| Azure | Subscription SID | `wso2_{subscriptionUuid}` | 80 chars |
| Kong | key-auth Secret | `wso2_{subscriptionUuid}` | No limit |
| Envoy | Secret name | `wso2_{subscriptionUuid}` | 253 chars (K8s limit) |

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
    REFERENCE_ARTIFACT LONGBLOB,                      -- Gateway-specific metadata (JSON)
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

## Part 6: Codebase Analysis - Current State

### 6.1 Gateway Feature Support Matrix

Based on analysis of `GatewayFeatureCatalog.json` files in each connector:

| Gateway | API Federation | Subscriptions Feature | Runtime Auth |
|---------|---------------|----------------------|--------------|
| **AWS** | ✅ `rest` | ❌ Empty `[]` | `oauth2` (Lambda) |
| **Azure** | ✅ `rest` | ❌ Empty `[]` | `cors`, `http/https` |
| **Kong** | ✅ `rest` | ✅ `["subscriptions"]` | `oauth2`, `apikey`, `keyManagerConfig` |
| **Envoy** | ✅ `rest` | ❌ Empty `[]` | `oauth2`, `apikey`, `basic`, `keyManagerConfig` |

**Key Finding:** Only **Kong** has subscription support implemented!

### 6.2 Kong Connector - Reference Implementation ✅

Kong connector **already implements our exact strategy**. Key components:

#### Consumer Management (Per-Application)
```
File: kong/gateway-connector/pkg/transformer/transformer.go
- CreateConsumer(applicationUUID, environment, conf) → *v1.KongConsumer
- GenerateConsumerName(applicationUUID, environment) → string (SHA1 hash-based)

File: kong/gateway-connector/internal/k8sClient/k8s_client.go
- DeployKongConsumerCR(consumer, k8sClient) → Creates/updates KongConsumer CR
- GetKongConsumerCR(name, k8sClient, conf) → Retrieves consumer
- UnDeployKongConsumerCR(name, k8sClient, conf) → Deletes consumer
```

#### Credential Management (Per-Subscription)
```
File: kong/gateway-connector/pkg/transformer/transformer.go
- GenerateK8sCredentialSecret(appUUID, identifier, credentialName, data) → *corev1.Secret
- CreateIssuerKongSecretCredential(...) → *corev1.Secret (for JWT)

File: kong/gateway-connector/pkg/transformer/utils.go
- GenerateACLGroupName(apiName, environment) → "api-{sha1}-{environment}"
- GenerateSecretName(appUUID, apiUUID, secretType) → "secret-{sha1}-{type}"
```

#### Subscription Event Handling
```
File: kong/gateway-connector/internal/events/subscription_handler.go
- HandleSubscriptionEvents(data, eventType, c) → Main event processor
- createSubscription(event, c, conf, env) → Creates ACL credentials
- updateSubscription(event, c, conf, env) → Updates state/policies
- removeSubscription(event, c, conf, env) → Removes credentials

File: kong/gateway-connector/pkg/synchronizer/subscriptions_fetcher.go
- CreateSubscription(appUUID, apiUUID, policyID, ..., aclGroupNames, ...) → Creates ACL Secret
- CreateApplicationConsumerForBothEnvironments(appUUID, c, conf) → Prod + Sandbox
```

#### Credential Types Used
```go
ACLCredentialType  = "acl"      // For subscription-based access
JWTCredentialType  = "jwt"      // For application key (OAuth)
KeyAuthPlugin      = "key-auth" // API key validation
ACLPlugin          = "acl"      // Access control lists
```

### 6.3 Envoy Connector - Partial Building Blocks ⚠️

Envoy has the infrastructure but not wired for subscriptions:

```
File: eg/gateway-connector/internal/k8sClient/k8s_client.go
- DeploySecretCR(secret, ownerRef, k8sClient) → Creates K8s Secrets ✅
- DeploySecurityPolicyCR(policy, ownerRef, k8sClient) → Creates SecurityPolicy ✅
- DeleteSecurityPolicyCR(k8sClient, policy) → Deletes policy ✅
- UpdateSecurityPolicyCRs(kmName, tenant, k8sClient, remove) → Updates policies ✅

Missing:
- Subscription event handler (like Kong's HandleSubscriptionEvents)
- Credential-to-SecurityPolicy wiring
```

### 6.4 AWS Connector - API Only ❌

AWS connector handles API deployment only:

```
File: aws/components/aws.gw.manager/src/main/java/org/wso2/aws/gw/client/
- AWSGatewayDeployer.java → Deploy/undeploy APIs
- AWSFederatedAPIDiscovery.java → Discover APIs
- AWSAPIUtil.java → Import/export API definitions
- GatewayUtil.java → Lambda authorizer setup

Missing (100% to implement):
- Usage Plan creation (per-API)
- API Key CRUD
- Attach key to Usage Plan
```

### 6.5 Azure Connector - API + Legacy Discovery ❌

Azure connector has API deployment. Application Discovery classes exist but are **out of scope** - do not depend on them for subscription management.

```
File: azure/components/azure.gw.manager/src/main/java/org/wso2/azure/gw/client/
- AzureGatewayDeployer.java → Deploy/undeploy APIs ✅
- AzureFederatedAPIDiscovery.java → Discover APIs ✅

Legacy (DO NOT DEPEND - observation only):
- AzureFederatedApplicationDiscovery.java → (Discovery pattern reference)
- AzureApplicationUtil.java → (Utility pattern reference)

Missing (to implement fresh):
- User creation (per-Application)
- Subscription CRUD (per-subscription)
- Key retrieval and regeneration
```

### 6.6 Implementation Priority

Based on existing code and effort required:

| Priority | Gateway | Effort | Approach |
|----------|---------|--------|----------|
| 1 | **Kong** | ✅ Done | Reference implementation - use as template |
| 2 | **Envoy** | 🟡 Low | Wire subscription events to existing Secret/Policy code |
| 3 | **Azure** | 🟠 Medium | Fresh implementation - User + Subscription CRUD |
| 4 | **AWS** | 🔴 High | Fresh implementation - Usage Plan + API Key CRUD |

### 6.7 Kong Patterns to Replicate

These Kong patterns should be replicated in other connectors:

1. **Event-Driven Architecture**
   ```
   HandleSubscriptionEvents() → createSubscription() / updateSubscription() / removeSubscription()
   ```

2. **Naming Convention**
   ```go
   GenerateConsumerName(appUUID, env) → SHA1-based unique name
   GenerateSecretName(appUUID, apiUUID, type) → Structured, filterable
   ```

3. **Two-Phase Credential Creation**
   ```
   Phase 1: Create Consumer/Container (per-app)
   Phase 2: Create Credential Secret (per-subscription)
   ```

4. **ACL-Based Access Control**
   ```
   Each API has ACL group → Subscription adds consumer to group
   ```

---

## Part 6B: Existing DTO Analysis - DevPortal Store API v1

### 6B.1 Key Existing DTOs

Based on analysis of `org.wso2.carbon.apimgt.rest.api.store.v1.dto`:

#### SubscriptionDTO (Current)
```java
public class SubscriptionDTO {
    private String subscriptionId;          // UUID of subscription
    private String applicationId;           // Required - UUID of app
    private String apiId;                   // UUID of API
    private APIInfoDTO apiInfo;             // Embedded API info
    private ApplicationInfoDTO applicationInfo;  // Embedded app info
    private String throttlingPolicy;        // Required - e.g., "Unlimited"
    private String requestedThrottlingPolicy;
    private StatusEnum status;              // BLOCKED, UNBLOCKED, ON_HOLD, REJECTED, etc.
    private String redirectionParams;       // URL for subscriber redirect
}
```

**Key Observation:** Current SubscriptionDTO has **no gateway/credential info** - it's purely about the WSO2-side subscription state.

#### APIInfoDTO (Current)
```java
public class APIInfoDTO {
    private String id;
    private String name, displayName, description;
    private String context, version, type;
    private String provider, lifeCycleStatus;
    private List<String> throttlingPolicies;
    private String gatewayType;             // ✅ Already exists! e.g., "solace"
    private String gatewayVendor;           // ✅ Already exists! e.g., "WSO2"
    private Boolean isSubscriptionAvailable;
    private Boolean egress;
    // ... more fields
}
```

**Key Observation:** `gatewayType` and `gatewayVendor` already exist! These can drive conditional credential logic.

#### ExternalGatewayEnvironmentDTO (Current)
```java
public class ExternalGatewayEnvironmentDTO {
    private String id;                      // UUID of gateway environment
    private String name;                    // e.g., "us-region"
    private String displayName;             // e.g., "US Region"
    private String type;                    // e.g., "hybrid", "production", "sandbox"
    private String gatewayType;             // e.g., "Regular", "APK"
    private String description;
}
```

**Key Observation:** Gateway environments are already modeled. Subscriptions on federated APIs need to link to these.

#### ApplicationKeyDTO (Current - OAuth focused)
```java
public class ApplicationKeyDTO {
    private String keyMappingId;
    private String keyManager;
    private String consumerKey;             // OAuth client ID
    private String consumerSecret;          // OAuth client secret
    private Object additionalProperties;
    private String keyType;                 // "PRODUCTION" or "SANDBOX"
    private String mode;                    // "MAPPED" or "CREATED"
    private String groupId;
    // ... OAuth-specific fields
}
```

**Key Observation:** Current key model is OAuth-centric. For federated subscriptions with opaque API keys, we need a **different DTO**.

### 6B.2 Gap Analysis for Federated Subscriptions

| Need | Current State | Gap |
|------|--------------|-----|
| Credential per subscription | ❌ No credential info in SubscriptionDTO | Need embedded or linked credential |
| Gateway environment context | ❌ Subscription doesn't reference environment | Need gatewayEnvId field |
| Invocation instructions | ❌ No URL/header info | Need InvocationInstructionDTO |
| Opaque API key storage | ❌ ApplicationKeyDTO is OAuth-focused | Need simpler FederatedCredentialDTO |
| External entity reference | ❌ No external IDs stored | Need externalSubscriptionId |

### 6B.3 Proposed New/Extended DTOs

#### Option A: Extend SubscriptionDTO (Recommended)
Add optional fields that only populate for federated APIs:

```java
public class SubscriptionDTO {
    // ... existing fields ...
    
    // NEW: Federation-specific fields (null for WSO2-native APIs)
    private FederatedSubscriptionInfoDTO federatedInfo;
}

public class FederatedSubscriptionInfoDTO {
    private String gatewayEnvironmentId;    // Which external gateway
    private String gatewayType;             // "aws", "azure", "kong", "envoy"
    private String externalSubscriptionId;  // Gateway-side ID
    private FederatedCredentialDTO credential;
    private InvocationInstructionDTO invocationInstruction;
}
```

#### Option B: Separate Endpoint (Alternative)
Keep SubscriptionDTO unchanged, add new endpoint:

```
GET /subscriptions/{subscriptionId}/credentials
→ Returns FederatedCredentialDTO

GET /subscriptions/{subscriptionId}/invocation-instructions
→ Returns InvocationInstructionDTO
```

**Recommendation:** Option A for simplicity - fewer API calls for developer UX.

### 6B.4 Proposed New DTOs

#### FederatedCredentialDTO
```java
public class FederatedCredentialDTO {
    private String credentialType;          // "api-key" (v1 only)
    private String credentialValue;         // Masked or full value
    private Boolean isValueRetrievable;     // AWS=false, others=true
    private String createdTime;
    private String expiresAt;               // Null if never expires
    private Boolean canRegenerate;          // True for all gateways
}
```

#### InvocationInstructionDTO
```java
public class InvocationInstructionDTO {
    private String gatewayType;             // "aws", "azure", "kong", "envoy"
    private String headerName;              // e.g., "x-api-key"
    private String headerValue;             // Credential value
    private String baseUrl;                 // e.g., "https://api.example.com"
    private String basePath;                // e.g., "/v1/weather"
    private String fullEndpoint;            // Combined URL
    private String curlExample;             // Pre-generated curl command
    private Map<String, String> additionalHeaders;  // Any extra headers
}
```

### 6B.5 API Endpoint Changes

#### Existing Endpoints (No Change Needed)
```
POST /subscriptions              → Creates subscription (input stays same)
GET  /subscriptions              → Lists subscriptions  
GET  /subscriptions/{id}         → Gets subscription details
DELETE /subscriptions/{id}       → Deletes subscription
```

#### Response Enhancement (for federated APIs)
When a subscription is for a federated API (`apiInfo.gatewayVendor != "WSO2"`), the response includes:

```json
{
  "subscriptionId": "uuid-123",
  "applicationId": "app-456",
  "apiId": "api-789",
  "apiInfo": {
    "name": "Weather API",
    "gatewayType": "aws",
    "gatewayVendor": "AWS"
  },
  "throttlingPolicy": "Unlimited",
  "status": "UNBLOCKED",
  
  // NEW - Only for federated APIs
  "federatedInfo": {
    "gatewayEnvironmentId": "env-abc",
    "gatewayType": "aws",
    "externalSubscriptionId": "aws-apikey-xyz789",
    "credential": {
      "credentialType": "api-key",
      "credentialValue": "••••••••ab12",
      "isValueRetrievable": false,
      "canRegenerate": true
    },
    "invocationInstruction": {
      "gatewayType": "aws",
      "headerName": "x-api-key",
      "baseUrl": "https://abc123.execute-api.us-east-1.amazonaws.com",
      "basePath": "/prod/weather",
      "fullEndpoint": "https://abc123.execute-api.us-east-1.amazonaws.com/prod/weather",
      "curlExample": "curl -H 'x-api-key: YOUR_KEY' https://..."
    }
  }
}
```

#### New Endpoint: Regenerate Key
```
POST /subscriptions/{id}/regenerate-credential
→ Regenerates key on external gateway
→ Returns updated FederatedCredentialDTO
```

#### New Endpoint: Get Full Credential (on-demand)
```
GET /subscriptions/{id}/credentials?reveal=true
→ Returns unmasked credential (for copy to clipboard)
→ Only works if isValueRetrievable=true
→ For AWS: Returns error (credential only available at creation time)
```

### 6B.6 Service Layer Integration

Based on existing service interfaces:

```java
// SubscriptionsApiService.java - existing interface
public interface SubscriptionsApiService {
    Response subscriptionsPost(SubscriptionDTO body, ...);  // Create
    Response subscriptionsGet(...);                          // List
    Response subscriptionsSubscriptionIdGet(id, ...);        // Get single
    Response subscriptionsSubscriptionIdDelete(id, ...);     // Delete
    Response subscriptionsMultiplePost(List<SubscriptionDTO> body, ...);  // Bulk create
}
```

**Proposed additions:**
```java
public interface SubscriptionsApiService {
    // ... existing methods ...
    
    // NEW: Regenerate federated credential
    Response subscriptionsSubscriptionIdRegenerateCredentialPost(
        String subscriptionId, MessageContext messageContext);
    
    // NEW: Reveal full credential (for copy)
    Response subscriptionsSubscriptionIdCredentialsGet(
        String subscriptionId, Boolean reveal, MessageContext messageContext);
}
```

### 6B.7 Backward Compatibility

| Scenario | Behavior |
|----------|----------|
| WSO2-native API subscription | `federatedInfo` = null, works exactly as before |
| Federated API subscription | `federatedInfo` populated with gateway-specific data |
| Old client reading new response | Ignores unknown `federatedInfo` field (JSON forward-compat) |
| Regenerate on WSO2-native API | Returns 400 Bad Request (not applicable) |

---

## Part 7: Implementation Phases (Revised)

### Phase 1: Research & Design ✅ (Current - Complete)
- [x] Document gateway consumer strategies
- [x] Define entity mappings
- [x] Define identifier patterns
- [x] Define supported actions
- [x] Design database schema
- [x] Analyze existing codebase
- [x] Identify Kong as reference implementation
- [ ] Review and finalize with stakeholders

### Phase 2: Core Abstractions
- [x] Create universal `SubscriptionAgent` interface (based on Kong pattern)
- [x] Define `InvocationInstruction` data model
- [x] Create `CredentialReference` model
- [x] Implement subscription external mapping DAO
- [x] Define event types for subscription lifecycle

### Phase 3: Gateway Agent Implementations

#### 3.1 Kong Agent ✅ (Already Complete)
- [x] Consumer management (per-Application)
- [x] key-auth credential operations
- [x] ACL management
- [x] Event-driven subscription handling
- **Status:** Reference implementation - use as template

#### 3.2 Envoy Agent 🟡 (Low Effort - Wire Existing Code)
- [ ] Add subscription event handler (follow Kong's `HandleSubscriptionEvents` pattern)
- [ ] Wire `CreateSubscription` to `DeploySecretCR` (already exists)
- [ ] Wire subscription to `DeploySecurityPolicyCR` reference updates
- [ ] Implement `removeSubscription` using existing `DeleteSecurityPolicyCR`
- [ ] Generate invocation instructions

#### 3.3 Azure Agent 🟠 (Medium Effort - Fresh Implementation)
- [ ] Implement Azure User creation (per-Application)
    - Use `manager.users().createOrUpdate()`
- [ ] Implement Azure Subscription CRUD (per-subscription)
    - Use `manager.subscriptions().createOrUpdate()` (API-scoped)
- [ ] Implement key retrieval via `manager.subscriptions().listSecrets()`
- [ ] Implement key regeneration via `manager.subscriptions().regeneratePrimaryKey()`
- [ ] Generate invocation instructions (Ocp-Apim-Subscription-Key header)

#### 3.4 AWS Agent 🔴 (High Effort - Full Implementation)
- [ ] Implement Usage Plan creation (per-API)
    - Use `createUsagePlan()` with API stage association
    - Naming: `wso2_{subscriptionUuid}`
- [ ] Implement API Key creation (per-subscription)
    - Use `createApiKey()`
    - Naming: `wso2_{subscriptionUuid}`
- [ ] Implement attach key to Usage Plan
    - Use `createUsagePlanKey()`
- [ ] Implement key deletion for unsubscribe
- [ ] Implement regenerate (delete + create new)
- [ ] Handle key value capture (only available at creation time!)
- [ ] Generate invocation instructions (x-api-key header)

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

## Part 8: POC Readiness - All Questions Resolved ✅

### 8.1 Summary - READY FOR POC IMPLEMENTATION

All blocking questions have been answered. The plan is ready for POC implementation.

| Component | Status | Notes |
|-----------|--------|-------|
| **Architecture** | ✅ Complete | Universal Control Plane model defined |
| **Entity Mappings** | ✅ Confirmed | All 5 gateways mapped |
| **Database Schema** | ✅ Designed | Uses existing patterns |
| **DTO Design** | ✅ Designed | Extends existing SubscriptionDTO |
| **Reference Implementation** | ✅ Exists | Kong connector |
| **Gateway Auth Pattern** | ✅ Resolved | Factory + encrypted environment properties |
| **API-Gateway Mapping** | ✅ Resolved | `AM_API_EXTERNAL_API_MAPPING` table |
| **Credential Strategy** | ✅ Resolved | One-time display, then masked |

### 8.2 Resolved Questions Summary

| # | Question | Answer |
|---|----------|--------|
| Q1 | Where is API-gateway relationship? | `AM_API_EXTERNAL_API_MAPPING` table |
| Q2 | Multi-gateway subscription? | Won't occur - one API → one gateway |
| Q3 | App across gateways? | Yes, confirmed earlier |
| Q4 | Gateway auth pattern? | Factory pattern with encrypted env properties |
| Q5 | Credential visibility? | One-time display at creation, masked afterward |
| Q6 | Error handling? | Fail fast for POC |
| Q7 | DAO location? | Add methods to `ApiMgtDAO.java` |

### 8.3 Key Implementation Patterns (From Existing Code)

#### Gateway Agent Factory Pattern
```java
// Follow FederatedApplicationDiscoveryFactory.java pattern
public class FederatedSubscriptionAgentFactory {
    public static FederatedSubscriptionAgent getAgent(Environment environment, String organization) {
        GatewayAgentConfiguration config = ServiceReferenceHolder.getInstance()
            .getExternalGatewayConnectorConfiguration(environment.getGatewayType());
        
        // Decrypt environment credentials
        Environment resolved = apiAdmin.getEnvironmentWithoutPropertyMasking(organization, environment.getUuid());
        resolved = apiAdmin.decryptGatewayConfigurationValues(resolved);
        
        // Instantiate and init agent
        FederatedSubscriptionAgent agent = Class.forName(config.getSubscriptionAgentImplementation()).newInstance();
        agent.init(resolved, organization);
        return agent;
    }
}
```

#### Credential Visibility Strategy
```java
// On CREATE subscription - return full key
FederatedCredentialDTO credential = new FederatedCredentialDTO();
credential.setCredentialValue(fullKeyValue);  // Full value!
credential.setIsInitialDisplay(true);

// On GET subscription - return masked
credential.setCredentialValue("••••••••" + lastFourChars);
credential.setIsInitialDisplay(false);

// On REGENERATE - return new full key
credential.setCredentialValue(newFullKeyValue);
credential.setIsInitialDisplay(true);
```

#### Database Lookup for API's Gateway
```sql
-- Find which gateway an API is deployed to
SELECT GATEWAY_ENV_ID 
FROM AM_API_EXTERNAL_API_MAPPING 
WHERE API_ID = ?
```

### 8.4 POC Scope

**Target Gateway:** Envoy (Kong already done)

**Deliverables:**
1. `FederatedSubscriptionAgent` interface
2. `FederatedSubscriptionAgentFactory` class
3. `EnvoyFederatedSubscriptionAgent` implementation
4. Database table + DAO methods in `ApiMgtDAO.java`
5. DTO extensions (FederatedSubscriptionInfoDTO, etc.)
6. REST API response enhancement

**Success Criteria:**
- ✅ Subscribe → Secret created in K8s
- ✅ Response shows full credential (one-time)
- ✅ GET shows masked credential
- ✅ Regenerate creates new credential
- ✅ Unsubscribe cleans up K8s resources

**Timeline:** ~1.5 weeks

### 8.5 Remaining Risks

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
*Next Review: After stakeholder feedback*****