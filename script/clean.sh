#!/usr/bin/env bash
# PicoBox Cleanup Script
# This script removes all build artifacts, logs, and temporary files to ensure a clean state.

set -e

# Ensure we are in the project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

echo "[Clean] Cleaning up PicoBox project..."

# 1. Remove Go binaries
if [ -d "bin" ]; then
    echo "[Clean] Removing bin/ directory..."
    rm -rf bin/
fi

# 2. Remove logs
echo "[Clean] Removing log files and logs/ directory..."
rm -f *.log
rm -rf logs/
rm -f web/web.log

# 3. Remove web build artifacts
if [ -d "web" ]; then
    echo "[Clean] Removing web build artifacts (.next, out)..."
    rm -rf web/.next web/out
fi

# 4. Remove generated API code (optional, keeping for now as per user preference)
# rm -rf api/gen/go/*

echo "[Clean] Cleanup completed successfully."
