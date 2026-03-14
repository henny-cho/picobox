#!/usr/bin/env bash
# PicoBox Go Dependency Update Script
# This script updates all Go dependencies to their latest versions and tidies the go.mod file.

set -e

echo "[Go-Deps] Starting Go dependency update..."

# Ensure we are in the project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

# 1. Update all dependencies to latest
echo "[Go-Deps] Fetching latest versions of all dependencies..."
go get -u ./...

# 2. Tidy go.mod and go.sum
echo "[Go-Deps] Tidying go.mod and go.sum..."
go mod tidy

echo "[Go-Deps] Go dependency update completed successfully."
