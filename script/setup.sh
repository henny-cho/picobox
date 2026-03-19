#!/usr/bin/env bash
# PicoBox Environment Setup Script
# This script is shared between CI/CD pipeline deployments and local development environments.
# It guarantees automation and idempotency, and continuously incorporates Lessons Learned related to dependencies and environment setup encountered during development.

set -e

echo "[Setup] Starting environment configuration for PicoBox..."

# 0. Load Version Configurations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/versions.sh"

# ==============================================================================
# 📝 KNOWLEDGE BASE
# ==============================================================================
# - Standardized to Go $GO_VERSION for gRPC & golangci-lint compatibility.
# - 'sudo' and 'iproute2' are essential for minimal CI (Act) environments.
# ==============================================================================

# 1. OS Dependencies
echo "[Setup] Checking system dependencies..."
CHECK_PACKAGES=(unzip libcap-dev curl python3 iproute2 sudo build-essential)
MISSING_PACKAGES=()

# Using dpkg-query for faster check
for pkg in "${CHECK_PACKAGES[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo "[Setup] Installing missing packages: ${MISSING_PACKAGES[*]}"
    if command -v sudo &> /dev/null; then
        sudo DEBIAN_FRONTEND=noninteractive LC_ALL=C apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive LC_ALL=C apt-get install -y "${MISSING_PACKAGES[@]}"
    else
        DEBIAN_FRONTEND=noninteractive LC_ALL=C apt-get update -qq && DEBIAN_FRONTEND=noninteractive LC_ALL=C apt-get install -y "${MISSING_PACKAGES[@]}"
    fi
else
    echo "[Setup] All system dependencies are already satisfied."
fi

# 2. Protobuf Compiler
echo "[Setup] Checking Protobuf Compiler (protoc)..."
if ! command -v protoc &> /dev/null || [[ $(protoc --version) != *"$PROTOC_VERSION"* ]]; then
    echo "[Setup] Fetching and installing Protobuf Compiler v$PROTOC_VERSION..."
    PROTOC_ZIP="protoc-$PROTOC_VERSION-linux-x86_64.zip"
    if [[ $(uname -m) == "aarch64" ]]; then PROTOC_ZIP="protoc-$PROTOC_VERSION-linux-aarch_64.zip"; fi
    
    curl -OL "https://github.com/protocolbuffers/protobuf/releases/download/v$PROTOC_VERSION/$PROTOC_ZIP"
    if command -v sudo &> /dev/null; then
        sudo unzip -o "$PROTOC_ZIP" -d /usr/local bin/protoc 'include/*'
    else
        unzip -o "$PROTOC_ZIP" -d /usr/local bin/protoc 'include/*'
    fi
    rm -f "$PROTOC_ZIP"
    echo "[Setup] protoc v$PROTOC_VERSION installed successfully."
else
    echo "[Setup] protoc is already installed ($(protoc --version))."
fi

# 3. Go Toolchain (pinned to $GO_VERSION)
echo "[Setup] Checking Go version..."
CURRENT_GO=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || echo "none")
if [ "$CURRENT_GO" == "$GO_VERSION" ]; then
    echo "[Setup] Go $GO_VERSION is already installed."
else
    echo "[Setup] Installing Go $GO_VERSION (Current: $CURRENT_GO)..."
    GO_ARCH="amd64"
    if [[ $(uname -m) == "aarch64" ]]; then GO_ARCH="arm64"; fi
    curl -OL "https://go.dev/dl/go$GO_VERSION.linux-$GO_ARCH.tar.gz"
    if command -v sudo &> /dev/null; then
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "go$GO_VERSION.linux-$GO_ARCH.tar.gz"
    else
        rm -rf /usr/local/go
        tar -C /usr/local -xzf "go$GO_VERSION.linux-$GO_ARCH.tar.gz"
    fi
    rm "go$GO_VERSION.linux-$GO_ARCH.tar.gz"
fi

# 4. Node.js & NPM (via NVM)
echo "[Setup] Checking Node.js and NPM..."

# Load NVM if it exists
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    source "$NVM_DIR/nvm.sh"
elif [ -s "/usr/local/bin/nvm" ]; then
    source "/usr/local/bin/nvm"
fi

if ! command -v nvm &> /dev/null; then
    echo "[Setup] Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
fi

echo "[Setup] Installing/Using Node.js $NODE_VERSION..."
nvm install "$NODE_VERSION"
nvm use "$NODE_VERSION"
nvm alias default "$NODE_VERSION"

echo "[Setup] Updating NPM to latest..."
npm install -g npm@latest

# 5. Go Plugins for Protobuf
echo "[Setup] Installing Go plugins (protoc-gen-go, protoc-gen-go-grpc)..."
export PATH=$PATH:/usr/local/go/bin
go install google.golang.org/protobuf/cmd/protoc-gen-go@$PROTOC_GEN_GO_VERSION
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@$PROTOC_GEN_GO_GRPC_VERSION


# 6. Update Go Dependencies
echo "[Setup] Updating Go dependencies..."
"$SCRIPT_DIR/update-go-deps.sh"

echo "[Setup] Environment setup completed successfully."
echo "[Setup] IMPORTANT: Please run 'export PATH=\$PATH:/usr/local/go/bin:$(go env GOPATH)/bin' or restart your shell."
