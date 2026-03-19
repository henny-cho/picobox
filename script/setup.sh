#!/usr/bin/env bash
# PicoBox Environment Setup Script
# This script is shared between CI/CD pipeline deployments and local development environments.
# It guarantees automation and idempotency, and continuously incorporates Lessons Learned related to dependencies and environment setup encountered during development.

set -e

# Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}[Setup] Starting environment configuration for PicoBox...${NC}"

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
echo -e "${CYAN}[Setup] Checking system dependencies...${NC}"
CHECK_PACKAGES=(unzip libcap-dev curl python3 iproute2 sudo build-essential)
MISSING_PACKAGES=()

# Using dpkg-query for faster check
for pkg in "${CHECK_PACKAGES[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo -e "${YELLOW}[Setup] Installing missing packages: ${MISSING_PACKAGES[*]}${NC}"
    if command -v sudo &> /dev/null; then
        sudo DEBIAN_FRONTEND=noninteractive LC_ALL=C apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive LC_ALL=C apt-get install -y "${MISSING_PACKAGES[@]}"
    else
        DEBIAN_FRONTEND=noninteractive LC_ALL=C apt-get update -qq && DEBIAN_FRONTEND=noninteractive LC_ALL=C apt-get install -y "${MISSING_PACKAGES[@]}"
    fi
else
    echo -e "${GREEN}[Setup] All system dependencies are already satisfied.${NC}"
fi

# 2. Protobuf Compiler
echo -e "${CYAN}[Setup] Checking Protobuf Compiler (protoc)...${NC}"
if ! command -v protoc &> /dev/null || [[ $(protoc --version) != *"$PROTOC_VERSION"* ]]; then
    echo -e "${YELLOW}[Setup] Fetching and installing Protobuf Compiler v$PROTOC_VERSION...${NC}"
    PROTOC_ZIP="protoc-$PROTOC_VERSION-linux-x86_64.zip"
    if [[ $(uname -m) == "aarch64" ]]; then PROTOC_ZIP="protoc-$PROTOC_VERSION-linux-aarch_64.zip"; fi
    
    curl -OL "https://github.com/protocolbuffers/protobuf/releases/download/v$PROTOC_VERSION/$PROTOC_ZIP"
    if command -v sudo &> /dev/null; then
        sudo unzip -o "$PROTOC_ZIP" -d /usr/local bin/protoc 'include/*'
    else
        unzip -o "$PROTOC_ZIP" -d /usr/local bin/protoc 'include/*'
    fi
    rm -f "$PROTOC_ZIP"
    echo -e "${GREEN}[Setup] protoc v$PROTOC_VERSION installed successfully.${NC}"
else
    echo -e "${GREEN}[Setup] protoc is already installed ($(protoc --version)).${NC}"
fi

# 3. Go Toolchain (pinned to $GO_VERSION)
echo -e "${CYAN}[Setup] Checking Go version...${NC}"
CURRENT_GO=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || echo "none")
if [ "$CURRENT_GO" == "$GO_VERSION" ]; then
    echo -e "${GREEN}[Setup] Go $GO_VERSION is already installed.${NC}"
else
    echo -e "${YELLOW}[Setup] Installing Go $GO_VERSION (Current: $CURRENT_GO)...${NC}"
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
echo -e "${CYAN}[Setup] Checking Node.js and NPM...${NC}"

# Load NVM if it exists
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    source "$NVM_DIR/nvm.sh"
elif [ -s "/usr/local/bin/nvm" ]; then
    source "/usr/local/bin/nvm"
fi

if ! command -v nvm &> /dev/null; then
    echo -e "${YELLOW}[Setup] Installing NVM...${NC}"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
fi

echo -e "${CYAN}[Setup] Installing/Using Node.js $NODE_VERSION...${NC}"
nvm install "$NODE_VERSION"
nvm use "$NODE_VERSION"
nvm alias default "$NODE_VERSION"

echo -e "${CYAN}[Setup] Updating NPM to latest...${NC}"
npm install -g npm@latest

# 5. Go Plugins for Protobuf
echo -e "${CYAN}[Setup] Installing Go plugins (protoc-gen-go, protoc-gen-go-grpc)...${NC}"
export PATH=$PATH:/usr/local/go/bin
go install google.golang.org/protobuf/cmd/protoc-gen-go@$PROTOC_GEN_GO_VERSION
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@$PROTOC_GEN_GO_GRPC_VERSION


# 6. Update Go Dependencies
echo -e "${CYAN}[Setup] Updating Go dependencies...${NC}"
"$SCRIPT_DIR/update-go-deps.sh"

echo -e "${GREEN}[Setup] Environment setup completed successfully.${NC}"
echo -e "${YELLOW}[Setup] IMPORTANT: Please run 'export PATH=\$PATH:/usr/local/go/bin:$(go env GOPATH)/bin' or restart your shell.${NC}"
