# Universal Gateway - Subscription Management Design

## Document Version
- **Created:** January 28, 2026
- **Last Updated:** January 30, 2026
- **Status:** ✅ IN PROGRESS - Core implementation underway
- **Scope:** AWS, Azure, Kong, Envoy Gateway

---

## Vision

Enable developers to subscribe to APIs deployed on external gateways (AWS, Azure, Kong, Envoy) through a **unified Developer Portal experience**. Developers simply:
1. Subscribe to API → Get a credential
2. View invocation instructions → See how to call the API
3. Gateway-specific details surface only at invocation time

---

## Architecture: Universal Control Plane Model

### Control Plane (WSO2) - Subscription Management

**Responsibilities:**
- ✅ Developer creates subscriptions in WSO2 DevPortal
- ✅ WSO2 enforces authorization (app ownership, API access policies)
- ✅ WSO2 orchestrates credential creation on external gateways
- ✅ WSO2 is the source of truth for subscription lifecycle

### Data Plane (Gateways) - Runtime Traffic

**Responsibilities:**
- ✅ Runtime API invocations go **directly to gateways** (bypass WSO2)
- ✅ Gateways validate credentials locally (no WSO2 introspection)
- ✅ Gateways enforce their own rate limits and policies
- ✅ Gateways handle analytics and metrics

### Critical Trade-offs

**WSO2 does NOT:**
- ❌ See runtime API traffic
- ❌ Enforce throttling at runtime (gateways use their own limits)
- ❌ Provide real-time analytics (must sync from gateways)

**WSO2 provides:**
- ✅ Unified subscription management across all gateways
- ✅ Single developer portal experience
- ✅ Centralized authorization

---

## Entity Mapping (Simplified Architecture)

| WSO2 Entity | AWS | Azure | Kong | Envoy |
|-------------|-----|-------|------|-------|
| **Organization** | Tag prefix | APIM Service | Namespace | Namespace |
| **Application** | *(none)* | *(none)* | *(none)* | *(labels only)* |
| **API** | Usage Plan | API | Route + ACL Plugin | HTTPRoute + SecurityPolicy |
| **Subscription** | API Key | Subscription | Consumer + key-auth | Secret |

### Key Design Decision: Simplified Entity Model

**Application-level entities are skipped on all gateways.** WSO2 is the sole control plane for enforcement (authorization, throttling, app ownership). Gateways are credential providers only.

**Rationale:**
- WSO2 already enforces app ownership before subscription creation
- Each subscription creates exactly one gateway entity
- Simpler lifecycle management (delete subscription = delete one entity)
- Consistent across all gateways

### What Gets Created When

| Event | AWS | Azure | Kong | Envoy |
|-------|-----|-------|------|-------|
| **API Deployed** | Usage Plan | *(API exists)* | Route + Service + ACL | HTTPRoute + SecurityPolicy |
| **App Created** | *(nothing)* | *(nothing)* | *(nothing)* | *(nothing)* |
| **Subscribe** | API Key → Usage Plan | Subscription (API-scoped) | Consumer + key-auth + ACL | Secret → SecurityPolicy |
| **Unsubscribe** | Delete API Key | Delete Subscription | Delete Consumer (cascades) | Delete Secret, update Policy |
| **Regenerate** | Delete + Create Key | Regenerate Primary Key | Delete + Create key-auth | Update Secret data |

---

## Key Generation & Credential Visibility

### Who Generates Keys?

| Gateway | Generator | Retrievable Later? |
|---------|-----------|-------------------|
| AWS | AWS | ❌ No - Only at creation |
| Azure | Azure | ✅ Yes - Via API |
| Kong | WSO2 (optional) | ✅ Yes - From Secret |
| Envoy | WSO2 | ✅ Yes - From Secret |

### Credential Visibility Strategy

- **CREATE/REGENERATE:** Return full key (one-time display to user)
- **GET:** Return masked key (`••••••••ab12`)
- **Rationale:** Simpler than encrypted storage, forces regeneration if lost

---

## Identifier Pattern

**Format:** `wso2_{subscriptionUuid}`

**Example:** `wso2_80369180-7d90-4ee8-99a1-19fa68512aa5`

- Total length: 41 characters
- Fits all gateway limits (AWS: 256, Azure: 80, Kong: unlimited, Envoy: 253)
- All context (org, app, API, env) stored in WSO2's `AM_SUBSCRIPTION_EXTERNAL_MAPPING` table

---

## Supported Authentication Types

### v1 Scope: Opaque API Keys Only

| Gateway | Header Name | Alternative |
|---------|-------------|-------------|
| AWS | `x-api-key` | - |
| Azure | `Ocp-Apim-Subscription-Key` | Query param: `subscription-key` |
| Kong | `apikey` (configurable) | Query param: `apikey` |
| Envoy | `x-api-key` (configurable) | - |

### Out of Scope (v1)

- ❌ OAuth2/JWT authentication
- ❌ mTLS / client certificates
- ❌ HMAC signatures
- ❌ Basic authentication

---

## Developer Actions

| Action | Description | Gateway Operations |
|--------|-------------|-------------------|
| **Subscribe** | Create subscription to API | Create credential on gateway |
| **Unsubscribe** | Remove subscription | Delete credential from gateway |
| **Regenerate Key** | Get new key, old invalidated | Delete old + create new |
| **View Instructions** | See how to invoke API | Gateway-specific URLs and headers |

---

## Subscription Support Check (NEW)

**Problem:** Some APIs on external gateways don't require subscriptions (e.g., Azure APIs with `subscriptionRequired: false`). Frontend needs to know this before showing subscription UI.

**Solution:** `GET /apis/{apiId}/subscription-support` endpoint

**Response:**
```json
{
  "supportedAuthTypes": ["opaque-api-key"],
  "requiresSubscription": true
}
```

OR (if no subscription needed):
```json
{
  "supportedAuthTypes": [],
  "requiresSubscription": false
}
```

**Implementation:** Agent queries external gateway to check security requirements.

---

## Database Schema

### AM_SUBSCRIPTION_EXTERNAL_MAPPING

Maps WSO2 subscriptions to external gateway entities.

| Column | Type | Description |
|--------|------|-------------|
| SUBSCRIPTION_UUID | VARCHAR(256) | WSO2 subscription ID (PK) |
| GATEWAY_ENV_ID | VARCHAR(255) | Gateway environment ID (PK) |
| EXTERNAL_SUBSCRIPTION_ID | VARCHAR(512) | Gateway's subscription identifier |
| REFERENCE_ARTIFACT | LONGBLOB | Gateway-specific metadata (JSON) |
| CREATED_TIME | TIMESTAMP | Creation timestamp |
| LAST_UPDATED_TIME | TIMESTAMP | Last update timestamp |

**Reference Artifact:** Contains gateway-specific invocation instructions, credential metadata, and external entity IDs.

---

## Reference Artifact Parsing

**Design Decision:** Connectors own their reference artifact format.

**Rationale:**
- Separation of concerns - REST API layer doesn't know gateway specifics
- Each connector knows how to parse its own metadata
- Extensible for future gateways

**Pattern:**
```java
InvocationInstruction instruction = agent.getInvocationInstruction(apiReferenceArtifact);
```

---

## REST API Endpoints

### Federated Subscription Endpoints

```
POST   /subscriptions/{id}/federated-subscription
  → Create credential on gateway, return full key

GET    /subscriptions/{id}/federated-subscription
  → Get masked credential + invocation instructions

DELETE /subscriptions/{id}/federated-subscription
  → Remove credential from gateway

POST   /subscriptions/{id}/regenerate-credential
  → Regenerate credential, return new full key

GET    /apis/{apiId}/subscription-support
  → Check if API requires subscriptions
```

---

## Implementation Status

### ✅ Completed (Azure Agent)

- [x] FederatedSubscriptionAgent interface
- [x] AzureFederatedSubscriptionAgent implementation
- [x] Database schema (AM_SUBSCRIPTION_EXTERNAL_MAPPING)
- [x] REST API endpoints (DevPortal)
- [x] DTOs (FederatedSubscriptionInfoDTO, FederatedCredentialDTO, etc.)
- [x] Subscription support check endpoint

### 🟡 In Progress

- [ ] Frontend UI integration
- [ ] End-to-end testing

### 🔴 Planned (Other Gateways)

- [ ] AWS Agent
- [ ] Envoy Agent
- [ ] Kong Agent (migrate existing)

---

## Key Design Decisions & Rationale

### 1. Application-Level Entities Skipped

**Decision:** Don't create Application entities on gateways (Azure Users, AWS containers, Kong Consumers for apps).

**Rationale:**
- WSO2 already enforces app ownership at subscription creation time
- Simplifies lifecycle (one entity per subscription)
- Gateways are credential providers, not authorization engines
- Consistent pattern across all gateways

### 2. Credential Storage Strategy

**Decision:** Store masked credentials only, user regenerates if forgotten.

**Rationale:**
- Simpler than encrypted storage
- Aligns with security best practices (credentials shown once)
- AWS doesn't support retrieval anyway

### 3. Synchronous Operations

**Decision:** Subscription operations are synchronous and fail-fast.

**Rationale:**
- Consistent state between WSO2 and gateway
- Simpler error handling
- If gateway fails, WSO2 subscription isn't created

### 4. Reference Artifact Parsing by Connector

**Decision:** Each connector parses its own reference artifact format.

**Rationale:**
- Separation of concerns
- REST API layer gateway-agnostic
- Extensible for future gateways

---

## Out of Scope (v1)

- ❌ Azure Products (API grouping) - Use API-scoped subscriptions only
- ❌ OAuth2/JWT authentication - Opaque API keys only
- ❌ Key rotation with grace period - Regenerate only
- ❌ Application-level rate limiting
- ❌ Externally-managed gateways (read-only brownfield)
- ❌ K8s Gateway controllers other than Envoy (Traefik, Contour)
- ❌ State reconciliation (if gateway entity deleted directly)
- ❌ WSO2 throttling policy mapping to gateway limits

---

## Security Considerations

1. **Never log credentials** - Use masked values in all logs
2. **Encrypt at rest** - Database encryption for reference artifacts
3. **HTTPS only** - All credential transmission over TLS
4. **One-time display** - Full key shown only at creation/regeneration
5. **Audit trail** - Log who accessed/regenerated (without values)
6. **Least privilege** - WSO2 service accounts have minimal gateway permissions

---

## Testing Strategy

### Unit Tests
- Mock gateway SDKs/clients
- Test credential masking logic
- Test DAO operations

### Integration Tests
- Deploy to test gateways (dev instances)
- End-to-end subscription flow
- Credential regeneration scenarios
- Error handling (gateway failures)

### Manual Testing
- DevPortal UI flow
- Credential copy/paste functionality
- Invocation instructions accuracy
- Gateway-specific validation

---

## Gateway SDK References

| Gateway | SDK/API | Documentation |
|---------|---------|---------------|
| AWS | `software.amazon.awssdk:apigateway` | [AWS API Gateway API](https://docs.aws.amazon.com/apigateway/latest/api/) |
| Azure | `azure-resourcemanager-apimanagement` | [Azure APIM REST API](https://docs.microsoft.com/en-us/rest/api/apimanagement/) |
| Kong | Kubernetes CRDs + Admin API | [Kong Admin API](https://docs.konghq.com/gateway/latest/admin-api/) |
| Envoy | Gateway API + Envoy CRDs | [Envoy Gateway Docs](https://gateway.envoyproxy.io/) |

---

## Related Documents

- **Implementation Guide:** `.project/CLAUDE.md` - For Claude Code AI assistant
- **Repository Guide:** `CLAUDE.md` - Navigation and repo structure
- **Legacy Design (Archived):** `.project/Application Federation.md` - Previous approach

---

## Approval & Sign-off

| Role | Name | Date | Signature |
|------|------|------|-----------

|
| Architect | | | |
| Tech Lead | | | |
| Product Owner | | | |

---

*Last updated: January 30, 2026*
