# WSO2 Build and Deploy Scripts

Simple scripts to build and deploy artifacts to WSO2 products.

## Prerequisites

Set these environment variables:

```bash
export WSO2_HOME=/path/to/wso2am
export WSO2_REPOS=/home/dasunw/development/repos
```

## Scripts

### 1. apply-patch.sh
Deploy a single artifact (JAR or WAR) to WSO2 product.

**Usage:**
```bash
./apply-patch.sh /full/path/to/pom.xml
```

**Example:**
```bash
./apply-patch.sh $WSO2_REPOS/wso2-apim-gw-connectors/azure/components/azure.gw.manager/pom.xml
```

**What it does:**
- For **JAR** files: Copies to `repository/components/dropins/`
- For **WAR** files: Deploys to `repository/deployment/server/webapps/`
- Automatically backs up old versions before deploying
- Old JARs from plugins are moved to `plugins/bak/`
- Old WARs and directories are moved to `webapps/bak/`

### 2. apply-all-patches.sh
Deploy all configured artifacts.

**Usage:**
```bash
./apply-all-patches.sh
```

**Deploys:**
1. `azure.gw.manager` → dropins/
2. `org.wso2.carbon.apimgt.api` → dropins/
3. `org.wso2.carbon.apimgt.impl` → dropins/
4. `org.wso2.carbon.apimgt.federated.gateway` → dropins/
5. `api#am#devportal.war` → webapps/

### 3. build-all.sh
Build all modules and deploy artifacts.

**Usage:**
```bash
# Build all modules
./build-all.sh

# Skip specific modules
./build-all.sh --skip-build azure,api
```

**Available modules:**
- `azure` - Azure gateway connector
- `api` - APIMGT API component
- `impl` - APIMGT Implementation component
- `fed` - APIMGT Federated Gateway
- `store` - APIMGT Store REST API (DevPortal)

## How It Works

1. **apply-patch.sh**: 
   - Reads POM to determine artifact type (JAR/WAR)
   - For JARs: Copies to dropins, backs up old versions from plugins
   - For WARs: Deploys to webapps, backs up existing war and directory
   
2. **apply-all-patches.sh**: 
   - Sequentially deploys all configured artifacts
   - Uses `apply-patch.sh` for each component

3. **build-all.sh**: 
   - Builds modules with Maven (skips tests)
   - Calls `apply-all-patches.sh` to deploy

After deployment, restart WSO2 server to apply changes.

