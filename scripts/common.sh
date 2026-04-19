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
check_command() {
    local cmd=$1
    local version_flag=${2:-"--version"}
    local expected_version=$3

    if ! command -v "$cmd" &> /dev/null; then
        return 1
    fi

    if [ -n "$expected_version" ]; then
        if [[ $("$cmd" "$version_flag" 2>&1) != *"$expected_version"* ]]; then
            return 2
        fi
    fi
    return 0
}

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
        log_error "Go is not installed. Please run ./scripts/task.sh setup first."
    fi
}

# ensure_go_tool <binary> <pkg@version> <version_substring>
# Installs the Go tool only when missing or when the version substring
# does not appear in `<binary> --version` output.
ensure_go_tool() {
    local bin_name=$1
    local pkg_spec=$2
    local version_substr=$3
    local bin_path
    bin_path=$(command -v "$bin_name" 2>/dev/null || true)
    if [ -n "$bin_path" ] && [ -n "$version_substr" ] && "$bin_name" --version 2>&1 | grep -q "$version_substr"; then
        log_info "$bin_name already at $version_substr."
        return 0
    fi
    log_info "Installing $pkg_spec..."
    go install "$pkg_spec"
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

# wait_for_log <file> <regex> <timeout_seconds> [label]
# Polls the log file for a regex match, sleeping 0.5s each tick.
# Returns 0 on match, non-zero on timeout.
wait_for_log() {
    local file=$1
    local pattern=$2
    local timeout=${3:-30}
    local label=${4:-"pattern"}
    local elapsed=0
    local interval_ms=500

    log_info "Waiting for $label in $(basename "$file") (timeout ${timeout}s)..."
    while [ "$elapsed" -lt "$((timeout * 1000))" ]; do
        if [ -f "$file" ] && grep -qE "$pattern" "$file" 2>/dev/null; then
            log_success "Matched $label after ${elapsed}ms."
            return 0
        fi
        sleep 0.5
        elapsed=$((elapsed + interval_ms))
    done
    log_warn "Timeout waiting for $label after ${timeout}s. Last 20 lines:"
    [ -f "$file" ] && tail -n 20 "$file" || echo "(log file missing)"
    return 1
}

# port_in_use <port> → exits 0 if bound.
port_in_use() {
    local port=$1
    ss -ltnH "sport = :$port" 2>/dev/null | grep -q LISTEN
}

# save_pid <name> <pid>
save_pid() {
    local name=$1
    local pid=$2
    mkdir -p "${LOG_DIR:-/tmp}"
    echo "$pid" > "${LOG_DIR:-/tmp}/${name}.pid"
}

# stop_pid_file <name>: kill the process tracked by <name>.pid, then remove the pidfile.
stop_pid_file() {
    local name=$1
    local pidfile="${LOG_DIR:-/tmp}/${name}.pid"
    [ -f "$pidfile" ] || return 0
    local pid
    pid=$(cat "$pidfile" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        log_info "Stopping $name (pid=$pid)..."
        kill -TERM "$pid" 2>/dev/null || true
        for _ in 1 2 3 4 5; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 1
        done
        kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
    fi
    rm -f "$pidfile"
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
        # Use pgrep -f to be more flexible with path-based binaries
        if pgrep -f "$name" > /dev/null; then
            log_info "Stopping all instances of $name..."
            pkill -15 -f "$name" || true
            sleep 2
            if pgrep -f "$name" > /dev/null; then
                log_warn "$name still running, forcing..."
                pkill -9 -f "$name" || true
            fi
            log_success "$name handled."
        fi
    fi
}

# Load local overrides if present (scripts/env.sh is gitignored).
if [ -f "$SCRIPT_DIR/env.sh" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/env.sh"
fi

# Ensure we are in the project root by default
cd "$ROOT_DIR"
