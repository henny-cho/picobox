#!/usr/bin/env bash
# PicoBox Common Utilities
# This script contains shared variables, colors, and helper functions.

# Color Definitions
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export CYAN='\033[0;36m'
export BLUE='\033[0;34m'
export MAGENTA='\033[0;35m'
export BOLD_RED='\033[1;31m'
export BOLD_GREEN='\033[1;32m'
export BOLD_YELLOW='\033[1;33m'
export BOLD_CYAN='\033[1;36m'
export BOLD_WHITE='\033[1;37m'
export NC='\033[0m'

# Project Directory Detection
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT_DIR="$(dirname "$SCRIPT_DIR")"
export BIN_DIR="$ROOT_DIR/bin"

# Binary Paths
export PICOBOXD_BIN="$BIN_DIR/picoboxd"
export PICOBOX_MASTER_BIN="$BIN_DIR/picobox-master"

# Logging Helpers
log_info() { echo -e "${CYAN}[INFO] $1${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}"; exit 1; }

# Environment Helpers
load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        source "$NVM_DIR/nvm.sh"
        if command -v nvm &> /dev/null; then
            nvm use "$NODE_VERSION" > /dev/null 2>&1 || true
        fi
    fi
}

ensure_go() {
    if ! command -v go &> /dev/null; then
        log_error "Go is not installed. Please run ./scripts/setup.sh first."
    fi
}

wait_for_port() {
    local host=$1
    local port=$2
    local timeout=${3:-15}
    local count=0
    log_info "Waiting for $host:$port to be ready..."
    while ! bash -c "< /dev/tcp/$host/$port" 2>/dev/null && [ $count -lt $timeout ]; do
        sleep 1
        echo -n "."
        count=$((count+1))
    done
    echo ""
    if [ $count -eq $timeout ]; then
        log_error "Timeout waiting for $host:$port"
    fi
}

format_code() {
    log_info "Cleaning trailing whitespace..."
    find "$ROOT_DIR" -type f \( -name "*.go" -o -name "*.tsx" -o -name "*.ts" -o -name "*.sh" -o -name "*.md" -o -name "*.css" \) \
        -not -path "*/node_modules/*" \
        -not -path "*/.git/*" \
        -not -path "*/.next/*" \
        -exec sed -i 's/[[:space:]]*$//' {} +
}

stop_process() {
    local identifier=$1
    local use_group=${2:-false}

    if [[ "$identifier" =~ ^[0-9]+$ ]]; then
        local pid=$identifier
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Stopping process $pid..."
            local target=$pid
            [ "$use_group" = true ] && target="-$pid"

            kill -15 "$target" 2>/dev/null || true

            # Wait up to 5 seconds
            for i in {1..5}; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    log_success "Process $pid terminated gracefully."
                    return 0
                fi
                sleep 1
            done

            log_warn "Process $pid did not exit gracefully, forcing..."
            kill -9 "$target" 2>/dev/null || true
        fi
    else
        local name=$identifier
        if pgrep -x "$name" > /dev/null; then
            log_info "Stopping all instances of $name..."
            pkill -15 -x "$name" || true
            sleep 2
            if pgrep -x "$name" > /dev/null; then
                log_warn "$name still running, forcing..."
                pkill -9 -x "$name" || true
            fi
            log_success "$name handled."
        fi
    fi
}

# Ensure we are in the project root by default
cd "$ROOT_DIR"
