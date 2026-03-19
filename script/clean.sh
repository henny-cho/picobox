#!/usr/bin/env bash
# PicoBox Cleanup Script
# This script removes all build artifacts, logs, and temporary files to ensure a clean state.

set -e

# Ensure we are in the project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

# Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}[Clean] Cleaning up PicoBox project...${NC}"

# 1. Remove Go binaries
if [ -d "bin" ]; then
    echo -e "${CYAN}[Clean] Removing bin/ directory...${NC}"
    rm -rf bin/
fi

# 2. Remove logs
echo -e "${CYAN}[Clean] Removing log files and logs/ directory...${NC}"
rm -f *.log
rm -rf logs/
rm -f web/web.log

# 3. Remove web build artifacts
if [ -d "web" ]; then
    echo -e "${CYAN}[Clean] Removing web build artifacts (.next, out)...${NC}"
    rm -rf web/.next web/out
fi

# 4. Remove generated API code (optional, keeping for now as per user preference)
# rm -rf internal/api/pb/*

echo -e "${GREEN}[Clean] Cleanup completed successfully.${NC}"
