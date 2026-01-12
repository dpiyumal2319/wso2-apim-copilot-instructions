# Application Discovery for Gateway Federation

## ℹ️ Project Overview

This project extends WSO2 API Manager's Gateway Federation to support **"Brownfield" environments**. Currently, the control plane is blind to existing consumers (API keys, subscriptions) on external gateways like Azure, AWS, and Kong. This feature allows Admins to **discover, list, and import** these existing consumers as WSO2 Applications, creating a unified control plane without disrupting existing traffic.

## 🏗️ Architecture

The solution uses a **Pull-Based Discovery Model**  to fetch entities from the external gateway's management API.

### Core Components

1. **Federation Agent**: A gateway-specific component (e.g., `AzureApplicationDiscovery`) that queries the external API.


2. **Resource Data Store**: Optimizes performance by batching policy/tier lookups to solve N+1 query problems.
3. **Reference Artifact Pattern**: A stateless mechanism to handle imports without persistence during the discovery phase.

## 🔄 Feature Workflow

### Phase 1: Discovery (The "Plain Sight" Rule)

The Agent queries the external gateway for native entities (Azure Subscriptions, AWS Keys).

* **Action**: Admin clicks "Discover Applications" in the Dev Portal.
* **Logic**: The Agent fetches credentials and maps them to a `DiscoveredApplication` DTO.
*
**Optimization**: 
- Uses server-side pagination (Limit/Offset) to handle large datasets efficiently.
- Since we do imports separately the agent should do most optimised data fetching to avoid N+1 query problems.



### Phase 2: Import (Onboarding)

To avoid re-fetching data during import, we use a **Reference Artifact**.

* **Mechanism**: The backend generates a JSON `referenceArtifact` containing the **External ID**, **Name**, and **Tier**.
* **Handoff**: This artifact is sent to the Frontend (Dev Portal) during listing.
* **Action**: When the user clicks **"Import"**, the Frontend sends this artifact (specifically the External ID) back to the backend.
*
**Result**: The backend uses the External ID to create the WSO2 Application and populates the `AM_APPLICATION_KEY_MAPPING` table.



## 🗺️ Entity Mapping Strategy (Azure Example)

We map native gateway concepts to WSO2 models based on "Plain Sight" availability.

| Azure Entity | WSO2 Concept | Mapping Logic |
| --- | --- | --- |
| **Subscription** | **Application** | `Subscription.DisplayName` becomes the Application Name. |
| **Product Policy** | **Tier** | `<rate-limit>` or `<rate-limit-by-key>` becomes the Throttling Tier. |
| **Subscription Key** | **Consumer Key** | The `Primary Key` is mapped as the external credential reference. |
| **Scope** | **Subscription** | Access to Products/APIs is mapped to WSO2 API Subscriptions. |

## 💻 Technical Implementation

* **Backend**: Java 11+, adhering to `FederatedApplicationDiscovery` interface.
* **Frontend**: React-based Dev Portal extensions (New "Discover" wizard).
*
**Security**: Imported applications are marked "Externally Managed". Secrets are masked or referenced by ID to prevent exposure.



## ✅ Deliverables

1. **Discovery Agent**: Implements fetching logic with pagination.
2. **Data Store**: Handles batch fetching and caching of tiers.
3. **REST API**: Endpoints for listing candidates and executing imports via Reference Artifact.
4. **UI**: "Discover Applications" view in the Developer Portal.

## 🎯 Current Status

### Azure Implementation: ✅ Complete

The Azure Application Discovery connector has been fully implemented with all phases complete:
- Discovery agent with pagination and search
- Product caching for tier extraction
- Secure key handling (masked display)
- Configuration and feature catalog updates

**Result:** 6 new classes, 4 modified files, ~1,500 lines of code

📄 **See [AZURE_IMPLEMENTATION.md](./AZURE_IMPLEMENTATION.md)** for complete technical documentation including:
- Entity mapping details (Subscription → Application)
- Reference artifact schema
- Security considerations
- Usage examples and API documentation
- Testing strategies
