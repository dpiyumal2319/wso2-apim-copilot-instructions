#!/bin/bash

# apply-all-patches.sh - Apply multiple patches at once

# =========================
# Colors & UI helpers
# =========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

ok()    { echo -e "${GREEN}✔${NC} $1"; }
warn()  { echo -e "${YELLOW}➜${NC} $1"; }
err()   { echo -e "${RED}✖${NC} $1"; }
info()  { echo -e "${CYAN}$1${NC}"; }
title() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# =========================
# Validation
# =========================
if [ -z "$WSO2_REPOS" ]; then
    err "WSO2_REPOS environment variable is not set"
    exit 1
fi

WSO2_PRODUCT_DIR="$WSO2_REPOS/wso2-product-apim/all-in-one-apim/modules/distribution/product/target/wso2am-4.6.0-SNAPSHOT"
PLUGINS_DIR="$WSO2_PRODUCT_DIR/repository/components/plugins"
WEBAPPS_DIR="$WSO2_PRODUCT_DIR/repository/deployment/server/webapps"

info "Applying all patches"
echo -e "${GRAY}WSO2 Product : $WSO2_PRODUCT_DIR${NC}\n"

# =========================
# Helpers
# =========================
convert_name() {
    echo "$1" | sed 's/-/_/' | sed 's/-/./'
}

copy_jar() {
    local source=$1
    local dest_dir=$2

    if [ ! -f "$source" ]; then
        err "Source not found: $source"
        return 1
    fi

    local filename dest_name dest
    filename=$(basename "$source")
    dest_name=$(convert_name "$filename")
    dest="$dest_dir/$dest_name"

    [ -f "$dest" ] && warn "Replacing $dest_name" || warn "Installing $dest_name"

    if cp "$source" "$dest"; then
        ok "Copied → $dest"
    else
        err "Copy failed"
        return 1
    fi
}

copy_war() {
    local source=$1
    local dest_dir=$2

    if [ ! -f "$source" ]; then
        err "Source not found: $source"
        return 1
    fi

    local filename dest_name dest webapp_dir
    filename=$(basename "$source")
    dest_name=$(convert_name "$filename")
    dest="$dest_dir/$dest_name"
    webapp_dir="$dest_dir/${dest_name%.war}"

    if [ -d "$webapp_dir" ]; then
        warn "Removing exploded webapp: ${dest_name%.war}"
        rm -rf "$webapp_dir"
    fi

    [ -f "$dest" ] && warn "Replacing $dest_name" || warn "Installing $dest_name"

    if cp "$source" "$dest"; then
        ok "Copied → $dest"
    else
        err "Copy failed"
        return 1
    fi
}

# =========================
# Patch Applications
# =========================
title "Azure Gateway Manager"
copy_jar \
"$WSO2_REPOS/wso2-apim-gw-connectors/azure/components/azure.gw.manager/target/azure.gw.manager-1.0.1-SNAPSHOT.jar" \
"$PLUGINS_DIR"

title "APIMGT API Component"
copy_jar \
"$WSO2_REPOS/wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.api/target/org.wso2.carbon.apimgt.api-9.32.160-SNAPSHOT.jar" \
"$PLUGINS_DIR"

title "APIMGT Implementation Component"
copy_jar \
"$WSO2_REPOS/wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.impl/target/org.wso2.carbon.apimgt.impl-9.32.160-SNAPSHOT.jar" \
"$PLUGINS_DIR"

title "APIMGT Federated Gateway"
copy_jar \
"$WSO2_REPOS/wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.federated.gateway/target/org.wso2.carbon.apimgt.federated.gateway-9.32.160-SNAPSHOT.jar" \
"$PLUGINS_DIR"

title "DevPortal REST API (Store v1)"
copy_war \
"$WSO2_REPOS/wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.rest.api.store.v1/target/api#am#devportal.war" \
"$WEBAPPS_DIR"

title "APIMGT REST API Common Component"
copy_jar \
"$WSO2_REPOS/wso2-carbon-apimgt/components/apimgt/org.wso2.carbon.apimgt.rest.api.common/target/org.wso2.carbon.apimgt.rest.api.common-9.32.160-SNAPSHOT.jar" \
"$PLUGINS_DIR"

# =========================
# Done
# =========================
echo
ok "All patches applied successfully"
info "Restart WSO2 server to apply changes"
