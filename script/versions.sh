#!/usr/bin/env bash
# PicoBox Version Configuration
# Centralized version definitions for all automation scripts.

# 🟢 Go & gRPC
export GO_VERSION="1.26.1"
export PROTOC_VERSION="34.0"
export PROTOC_GEN_GO_VERSION="v1.36.11"
export PROTOC_GEN_GO_GRPC_VERSION="v1.6.1"

# 🔵 Node.js & Web
export NODE_VERSION="24"

# 🟠 CI/CD Tools
export GOLANGCI_LINT_VERSION="v2.11.3"

# ==============================================================================
# 🛠️ Environment Helpers
# ==============================================================================
# Ensure Go binaries are in PATH
export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"

# Function to reliably load NVM and correct Node version
load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        source "$NVM_DIR/nvm.sh"
        if command -v nvm &> /dev/null; then
            nvm use "$NODE_VERSION" > /dev/null 2>&1 || true
        fi
    fi
}
