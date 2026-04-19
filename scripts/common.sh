#!/usr/bin/env bash
# PicoBox shared shell library.
#
# Contract:
#   - Idempotent to source. No side effects beyond variable exports and
#     function definitions (callers decide whether to cd, etc.).
#   - Pulls in pinned tool versions via versions.sh.
#   - Sources scripts/env.sh at the end if the file exists, so local
#     overrides win over the defaults defined above.

# -----------------------------------------------------------------------------
# Project paths (safe to re-source; computed from this file's location)
# -----------------------------------------------------------------------------
_COMMON_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR="$_COMMON_SH_DIR"
export ROOT_DIR="$(dirname "$SCRIPT_DIR")"
export BIN_DIR="$ROOT_DIR/bin"

# Binary paths (absolute)
export PICOBOXD_BIN="$BIN_DIR/picoboxd"
export PICOBOX_MASTER_BIN="$BIN_DIR/picobox-master"

# Runtime directories (defaults; env.sh may override)
export LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
export PICOBOX_STORAGE_DIR="${PICOBOX_STORAGE_DIR:-$ROOT_DIR/.storage}"

# -----------------------------------------------------------------------------
# Pinned tool versions
# -----------------------------------------------------------------------------
# shellcheck source=versions.sh
source "$SCRIPT_DIR/versions.sh"

# -----------------------------------------------------------------------------
# ANSI colors
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Logging helpers. log_error intentionally terminates the caller.
# -----------------------------------------------------------------------------
log_info()    { echo -e "${CYAN}[INFO] $1${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
log_warn()    { echo -e "${YELLOW}[WARN] $1${NC}"; }
log_error()   { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Command / version checks
# -----------------------------------------------------------------------------
# check_command <cmd> [version_flag=--version] [expected_substring]
# Returns 0 if present (and matches version if given), 1 if missing, 2 if mismatch.
check_command() {
    local cmd=$1
    local version_flag=${2:-"--version"}
    local expected=$3

    command -v "$cmd" &> /dev/null || return 1
    [ -z "$expected" ] && return 0
    [[ $("$cmd" "$version_flag" 2>&1) == *"$expected"* ]] && return 0
    return 2
}

# ensure_go: hard-fail if Go is missing.
ensure_go() {
    command -v go &> /dev/null \
        || log_error "Go is not installed. Run ./scripts/task.sh setup first."
}

# ensure_go_tool <binary> <pkg@version> <version_substring>
# Installs the Go tool only when missing or when the version substring
# does not appear in `<binary> --version` output.
ensure_go_tool() {
    local bin_name=$1
    local pkg_spec=$2
    local version_substr=$3
    if command -v "$bin_name" &> /dev/null && [ -n "$version_substr" ] \
        && "$bin_name" --version 2>&1 | grep -q "$version_substr"; then
        log_info "$bin_name already at $version_substr."
        return 0
    fi
    log_info "Installing $pkg_spec..."
    go install "$pkg_spec"
}

# load_nvm: opportunistic nvm activation. No-op if nvm isn't installed.
load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        # shellcheck source=/dev/null
        source "$NVM_DIR/nvm.sh"
        command -v nvm &> /dev/null && nvm use "$NODE_VERSION" > /dev/null 2>&1 || true
    fi
}

# -----------------------------------------------------------------------------
# Readiness helpers
# -----------------------------------------------------------------------------
# wait_for_port <host> <port> [timeout_seconds=15]
wait_for_port() {
    local host=$1 port=$2 timeout=${3:-15} elapsed=0
    log_info "Waiting for $host:$port (timeout ${timeout}s)..."
    while ! bash -c "< /dev/tcp/$host/$port" 2>/dev/null; do
        [ "$elapsed" -ge "$timeout" ] && log_error "Timeout waiting for $host:$port"
        sleep 1
        elapsed=$((elapsed + 1))
    done
    log_success "$host:$port reachable after ${elapsed}s."
}

# wait_for_log <file> <regex> [timeout_seconds=30] [label="pattern"]
# Polls the log file for a regex match, 0.5s interval. Returns 0 on match, 1 on timeout.
wait_for_log() {
    local file=$1 pattern=$2 timeout=${3:-30} label=${4:-"pattern"}
    local elapsed_ms=0

    log_info "Waiting for $label in $(basename "$file") (timeout ${timeout}s)..."
    while [ "$elapsed_ms" -lt "$((timeout * 1000))" ]; do
        if [ -f "$file" ] && grep -qE "$pattern" "$file" 2>/dev/null; then
            log_success "Matched $label after ${elapsed_ms}ms."
            return 0
        fi
        sleep 0.5
        elapsed_ms=$((elapsed_ms + 500))
    done
    log_warn "Timeout waiting for $label after ${timeout}s. Last 20 lines:"
    [ -f "$file" ] && tail -n 20 "$file" || echo "(log file missing)"
    return 1
}

# port_in_use <port> → exit 0 if bound.
port_in_use() {
    local port=$1
    ss -ltnH "sport = :$port" 2>/dev/null | grep -q LISTEN
}

# -----------------------------------------------------------------------------
# PID-file based process tracking ($LOG_DIR/<name>.pid)
# -----------------------------------------------------------------------------
save_pid() {
    local name=$1 pid=$2
    mkdir -p "$LOG_DIR"
    echo "$pid" > "$LOG_DIR/${name}.pid"
}

# stop_pid_file <name>: TERM the tracked process, wait up to 5s, KILL if needed.
stop_pid_file() {
    local name=$1
    local pidfile="$LOG_DIR/${name}.pid"
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

# -----------------------------------------------------------------------------
# Local overrides (scripts/env.sh is gitignored)
# -----------------------------------------------------------------------------
if [ -f "$SCRIPT_DIR/env.sh" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/env.sh"
fi
