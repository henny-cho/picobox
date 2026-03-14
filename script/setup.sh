#!/usr/bin/env bash
# PicoBox Environment Setup Script
# This script is shared between CI/CD pipeline deployments and local development environments.
# It guarantees automation and idempotency, and continuously incorporates Lessons Learned related to dependencies and environment setup encountered during development.

set -e

echo "[Setup] Starting environment configuration for PicoBox..."

# ==============================================================================
# 📝 LESSONS LEARNED & KNOWLEDGE BASE
# ==============================================================================
# [Date: 2026-03-14]
# Issue: Go 1.25.0 causes compatibility issues with golangci-lint and gRPC symbols.
# Resolution: Pin toolchain to Go 1.24.2 and google.golang.org/grpc to v1.64.0+.
# [Date: 2026-03-15]
# Issue: Minimal CI environments (Act) lack 'sudo' and 'ss' command.
# Resolution: Add 'sudo' and 'iproute2' (for ss) to apt-get installation list.
# ==============================================================================

# 1. OS Dependencies
echo "[Setup] Checking system dependencies..."
CHECK_PACKAGES=(unzip libcap-dev curl python3 iproute2 sudo)
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
        sudo apt-get update -qq && sudo apt-get install -y "${MISSING_PACKAGES[@]}"
    else
        apt-get update -qq && apt-get install -y "${MISSING_PACKAGES[@]}"
    fi
else
    echo "[Setup] All system dependencies are already satisfied."
fi

# 2. Protobuf Compiler
echo "[Setup] Checking Protobuf Compiler (protoc)..."
if ! command -v protoc &> /dev/null; then
    echo "[Setup] Fetching and installing Protobuf Compiler..."
    PROTOC_ZIP="protoc-24.0-linux-x86_64.zip"
    if [[ $(uname -m) == "aarch64" ]]; then PROTOC_ZIP="protoc-24.0-linux-aarch_64.zip"; fi
    
    curl -OL "https://github.com/protocolbuffers/protobuf/releases/download/v24.0/$PROTOC_ZIP"
    if command -v sudo &> /dev/null; then
        sudo unzip -o "$PROTOC_ZIP" -d /usr/local bin/protoc 'include/*'
    else
        unzip -o "$PROTOC_ZIP" -d /usr/local bin/protoc 'include/*'
    fi
    rm -f "$PROTOC_ZIP"
    echo "[Setup] protoc installed successfully."
else
    echo "[Setup] protoc is already installed ($(protoc --version))."
fi

# 3. Go Toolchain (pinned to 1.24.2)
echo "[Setup] Checking Go version..."
CURRENT_GO=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || echo "none")
if [ "$CURRENT_GO" == "1.24.2" ]; then
    echo "[Setup] Go 1.24.2 is already installed."
else
    echo "[Setup] Installing Go 1.24.2 (Current: $CURRENT_GO)..."
    GO_ARCH="amd64"
    if [[ $(uname -m) == "aarch64" ]]; then GO_ARCH="arm64"; fi
    curl -OL "https://go.dev/dl/go1.24.2.linux-$GO_ARCH.tar.gz"
    if command -v sudo &> /dev/null; then
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "go1.24.2.linux-$GO_ARCH.tar.gz"
    else
        rm -rf /usr/local/go
        tar -C /usr/local -xzf "go1.24.2.linux-$GO_ARCH.tar.gz"
    fi
    rm "go1.24.2.linux-$GO_ARCH.tar.gz"
fi

# 4. Go Plugins for Protobuf
echo "[Setup] Installing Go plugins (protoc-gen-go, protoc-gen-go-grpc)..."
export PATH=$PATH:/usr/local/go/bin
go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.33.0
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.2.0


echo "[Setup] Environment setup completed successfully."
echo "[Setup] IMPORTANT: Please run 'export PATH=\$PATH:/usr/local/go/bin:$(go env GOPATH)/bin' or restart your shell."
