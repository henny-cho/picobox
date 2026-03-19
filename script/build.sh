#!/usr/bin/env bash
# PicoBox Build Script
# This script automates the compilation of communication formats (Protobuf) and the building of daemon/master nodes within the monorepo architecture.

set -e

# Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD_RED='\033[1;31m'
BOLD_GREEN='\033[1;32m'
BOLD_YELLOW='\033[1;33m'
BOLD_CYAN='\033[1;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}[Build] Starting build process for PicoBox...${NC}"

# 0. Load Version Configurations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/versions.sh"

# ==============================================================================
# 📝 KNOWLEDGE BASE: Standardized to Go $GO_VERSION for stability.
# ==============================================================================
# Ensure basic Go requirement is roughly matched instead of failing on minor mismatches
if ! command -v go &> /dev/null; then
    echo -e "${RED}[Build] ERROR: Go is not installed or not in PATH.${NC}"
    echo -e "${YELLOW}[Build] Please run ./script/setup.sh first.${NC}"
    exit 1
fi

CURRENT_GO=$(go version | awk '{print $3}' | sed 's/go//')
if [[ "$CURRENT_GO" != "$GO_VERSION"* ]]; then
    echo -e "${YELLOW}[Build] WARNING: Go version $CURRENT_GO is different from requested $GO_VERSION.${NC}"
fi

# ==============================================================================
# 🔵 Node.js Environment (NVM)
# ==============================================================================
load_nvm
if command -v node &> /dev/null; then
    echo -e "${CYAN}[Build] Using Node $(node -v) (NPM $(npm -v))${NC}"
else
    echo -e "${YELLOW}[Build] WARNING: Node not found in PATH.${NC}"
fi

# Ensure we are in the project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

# 1. Protobuf Compilation
echo -e "${CYAN}[Build] Step 1: Compiling Protobuf...${NC}"
if [ -f "api/proto/picobox.proto" ]; then
    # Ensure output directory exists
    rm -rf internal/api/pb
    mkdir -p internal/api/pb
    # Ensure protoc plugin binary path is in PATH
    export PATH="$PATH:$(go env GOPATH)/bin"
    protoc -Iapi/proto --go_out=internal/api/pb --go_opt=paths=source_relative \
           --go-grpc_out=internal/api/pb --go-grpc_opt=paths=source_relative \
           picobox.proto
    echo -e "${GREEN}[Build] Protobuf generated in internal/api/pb.${NC}"
else
    echo -e "${YELLOW}[Build] Skipping Protobuf compilation (api/proto/picobox.proto not found yet).${NC}"
fi

# 2. Go Binary Build (Daemon & Master)
build_go() {
    echo -e "${CYAN}[Build] Step 2: Building Go Binaries...${NC}"
    if [ -d "cmd/picoboxd" ]; then
        go build -o bin/picoboxd ./cmd/picoboxd
        echo -e "${GREEN}[Build] picoboxd daemon built.${NC}"
    fi

    if [ -d "cmd/picobox-master" ]; then
        go build -o bin/picobox-master ./cmd/picobox-master
        echo -e "${GREEN}[Build] picobox-master built.${NC}"
    fi
}

# 3. Next.js Web Dashboard Build
build_web() {
    echo -e "${CYAN}[Build] Step 3: Building Next.js Web Dashboard...${NC}"
    if [ -d "web" ] && [ -f "web/package.json" ]; then
        echo -e "${CYAN}[Build] Compiling Web frontend...${NC}"
        (cd web && npm ci && npm run build)
        echo -e "${GREEN}[Build] Next.js build completed.${NC}"
    fi
}

# Run builds in parallel
build_go &
GO_PID=$!

build_web &
WEB_PID=$!

# Wait for both and check status
EXIT_CODE=0
wait $GO_PID || EXIT_CODE=$?
wait $WEB_PID || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo -e "${RED}[Build] ERROR: Build failed with exit code $EXIT_CODE${NC}"
    exit $EXIT_CODE
fi

echo -e "${GREEN}[Build] Build process completed successfully.${NC}"
