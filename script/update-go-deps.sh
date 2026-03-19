#!/usr/bin/env bash
# PicoBox Go Dependency Update Script
# This script updates all Go dependencies to their latest versions and tidies the go.mod file.

set -e

# Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}[Go-Deps] Starting Go dependency update...${NC}"

# Ensure we are in the project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

# 1. Update all dependencies to latest
echo -e "${CYAN}[Go-Deps] Fetching latest versions of all dependencies...${NC}"
go get -u ./...

# 2. Tidy go.mod and go.sum
echo -e "${CYAN}[Go-Deps] Tidying go.mod and go.sum...${NC}"
go mod tidy

echo -e "${GREEN}[Go-Deps] Go dependency update completed successfully.${NC}"
