#!/usr/bin/env bash
# PicoBox Build Script
# This script automates the compilation of communication formats (Protobuf) and the building of daemon/master nodes within the monorepo architecture.

set -e

echo "[Build] Starting build process for PicoBox..."

# 0. Load Version Configurations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/versions.sh"

# ==============================================================================
# 📝 KNOWLEDGE BASE: Standardized to Go $GO_VERSION for stability.
# ==============================================================================
# Ensure basic Go requirement is roughly matched instead of failing on minor mismatches
if ! command -v go &> /dev/null; then
    echo "[Build] ERROR: Go is not installed or not in PATH."
    echo "[Build] Please run ./script/setup.sh first."
    exit 1
fi

CURRENT_GO=$(go version | awk '{print $3}' | sed 's/go//')
if [[ "$CURRENT_GO" != "$GO_VERSION"* ]]; then
    echo "[Build] WARNING: Go version $CURRENT_GO is different from requested $GO_VERSION."
fi

# ==============================================================================
# 🔵 Node.js Environment (NVM)
# ==============================================================================
load_nvm
if command -v node &> /dev/null; then
    echo "[Build] Using Node $(node -v) (NPM $(npm -v))"
else
    echo "[Build] WARNING: Node not found in PATH."
fi

# Ensure we are in the project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

# 1. Protobuf Compilation
echo "[Build] Step 1: Compiling Protobuf..."
if [ -f "api/proto/picobox.proto" ]; then
    # Ensure output directory exists
    rm -rf internal/api/pb
    mkdir -p internal/api/pb
    # Ensure protoc plugin binary path is in PATH
    export PATH="$PATH:$(go env GOPATH)/bin"
    protoc -Iapi/proto --go_out=internal/api/pb --go_opt=paths=source_relative \
           --go-grpc_out=internal/api/pb --go-grpc_opt=paths=source_relative \
           picobox.proto
    echo "[Build] Protobuf generated in internal/api/pb."
else
    echo "[Build] Skipping Protobuf compilation (api/proto/picobox.proto not found yet)."
fi

# 2. Go Binary Build (Daemon & Master)
build_go() {
    echo "[Build] Step 2: Building Go Binaries..."
    if [ -d "cmd/picoboxd" ]; then
        go build -o bin/picoboxd ./cmd/picoboxd
        echo "[Build] picoboxd daemon built."
    fi

    if [ -d "cmd/picobox-master" ]; then
        go build -o bin/picobox-master ./cmd/picobox-master
        echo "[Build] picobox-master built."
    fi
}

# 3. Next.js Web Dashboard Build
build_web() {
    echo "[Build] Step 3: Building Next.js Web Dashboard..."
    if [ -d "web" ] && [ -f "web/package.json" ]; then
        echo "[Build] Compiling Web frontend..."
        (cd web && npm ci && npm run build)
        echo "[Build] Next.js build completed."
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
    echo "[Build] ERROR: Build failed with exit code $EXIT_CODE"
    exit $EXIT_CODE
fi

echo "[Build] Build process completed successfully."
