#!/bin/bash

# build-all.sh - Build packages
# Usage: ./build-all.sh [--skip-build module1,module2,...]
# Example: ./build-all.sh --skip-build azure,api

set -e  # Exit on error

if [ -z "$WSO2_HOME" ]; then
    echo "Error: WSO2_HOME environment variable is not set"
    exit 1
fi

if [ -z "$WSO2_REPOS" ]; then
    echo "Error: WSO2_REPOS environment variable is not set"
    exit 1
fi

# Define all modules with their paths (relative to WSO2_REPOS)
declare -A MODULES=(
    ["api"]="wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.api"
    ["azure"]="wso2-apim-gw-connectors/azure"
    ["impl"]="wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.impl"
    ["fed"]="wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.federated.gateway"
    ["store"]="wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.rest.api.store.v1"
    ["common"]="wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.rest.api.common"
)

# Parse command line arguments
SKIP_BUILDS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            IFS=',' read -ra SKIP_BUILDS <<< "$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--skip-build module1,module2,...]"
            echo "Available modules: ${!MODULES[@]}"
            exit 1
            ;;
    esac
done

# Function to check if module should be skipped
should_skip() {
    local module=$1
    for skip in "${SKIP_BUILDS[@]}"; do
        if [ "$skip" == "$module" ]; then
            return 0
        fi
    done
    return 1
}

echo "========================================="
echo "WSO2 Build & Deploy Script"
echo "========================================="
echo ""

MODULE_ORDER=(
    api
    azure
    impl
    fed
    store
    common
)

# Build phase
echo "PHASE 1: Building modules"
echo "-----------------------------------------"
for module in "${MODULE_ORDER[@]}"; do
    if should_skip "$module"; then
        echo "⊘ Skipping build for: $module"
        continue
    fi

    module_path="${MODULES[$module]}"
    echo ""
    echo "Building: $module ($module_path)"
    echo "Command: mvn clean install -Dmaven.test.skip=true -DskipTests"

    if [ ! -d "$WSO2_REPOS/$module_path" ]; then
        echo "Error: Module path not found: $WSO2_REPOS/$module_path"
        exit 1
    fi

    cd "$WSO2_REPOS/$module_path"
    mvn clean install -Dmaven.test.skip=true -DskipTests

    echo "✓ Successfully built: $module"
done