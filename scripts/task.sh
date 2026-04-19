#!/usr/bin/env bash
# PicoBox task runner.
#
# Thin dispatcher over small, well-scoped commands. Each command below has a
# single responsibility; complex multi-step flows (E2E) live in their own
# scripts and are invoked from here.
#
# Layout:
#   scripts/common.sh         — shared helpers (logging, wait_for_*, PID files)
#   scripts/versions.sh       — pinned tool versions
#   scripts/task.sh           — this dispatcher
#   scripts/e2e.sh            — full-stack E2E suite (`task.sh e2e` delegates)
#   scripts/prepare-rootfs.sh — busybox rootfs for sandbox tests
#   scripts/install-daemon.sh — systemd install helper
#
# Usage: ./scripts/task.sh <command> [options]
#        ./scripts/task.sh help

set -euo pipefail
IFS=$'\n\t'

_TASK_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$_TASK_SH_DIR/common.sh"

cd "$ROOT_DIR"
mkdir -p "$LOG_DIR" "$PICOBOX_STORAGE_DIR"

# Ensure locally-installed tools win over stale system copies.
export PATH="$ROOT_DIR/.tools/bin:$(go env GOPATH 2>/dev/null || echo "$HOME/go")/bin:$PATH"

# -----------------------------------------------------------------------------
# Command table. Format: "<name>|<handler>|<one-line description>".
# print_usage renders this; the router dispatches through it.
# -----------------------------------------------------------------------------
COMMANDS=(
    "setup|do_setup|Install system deps, toolchains, and Go plugins. Pass 'ci' in CI."
    "doctor|do_doctor|Verify kernel, cgroups, toolchain, and runtime deps."
    "proto|do_proto|Regenerate gRPC Go stubs from api/proto/picobox.proto."
    "build|do_build|Build proto + Go (agent/master) + Web. No source mutation."
    "run|do_run|Start master, agent, and web dashboard for development."
    "stop|do_stop|Stop background processes tracked via logs/*.pid."
    "logs|do_logs|Tail service logs. Usage: logs [master|agent|web|all|clear] [lines]."
    "test|do_test|Run tests. Modes: unit (default), regression, local (act)."
    "e2e|do_e2e|Run full-stack E2E suite (scripts/e2e.sh). Accepts --skip-build."
    "ci|do_ci|Reproduce CI's lint+test locally (fmt:check -> lint -> test unit)."
    "fmt|do_fmt|Apply gofmt and trim trailing whitespace."
    "fmt:check|do_fmt_check|Verify formatting without modifying files."
    "lint|do_lint|Run golangci-lint over all Go packages."
    "tidy|do_tidy|Run 'go mod tidy'."
    "release|do_release|Build production binaries with version metadata + checksums."
    "clean|do_clean|Remove build outputs (bin/, web/.next, logs/, node_modules)."
    "clean:data|do_clean_data|Remove runtime storage (.storage/). Destructive — requires PICOBOX_CONFIRM_CLEAN_DATA=yes."
    "help|print_usage|Show this help."
)

print_usage() {
    echo -e "${BOLD_CYAN}PicoBox Task Runner${NC}"
    echo -e "Usage: ./scripts/task.sh <command> [options]\n"
    echo -e "${BOLD_WHITE}COMMANDS:${NC}"
    local row name handler desc
    for row in "${COMMANDS[@]}"; do
        IFS='|' read -r name handler desc <<< "$row"
        printf "  ${CYAN}%-12s${NC}  %s\n" "$name" "$desc"
    done
    echo
    echo -e "${BOLD_WHITE}TYPICAL FLOWS${NC}"
    echo "  First time:                ./scripts/task.sh setup && ./scripts/task.sh doctor"
    echo "  Build + run locally:       ./scripts/task.sh build && ./scripts/task.sh run"
    echo "  Reproduce CI locally:      ./scripts/task.sh ci"
    echo "  Full integration check:    sudo -E ./scripts/task.sh e2e"
    echo
    echo -e "${BOLD_WHITE}ENVIRONMENT${NC}"
    echo "  PICOBOX_API_TOKEN          Shared secret between master and agent."
    echo "  PICOBOX_STORAGE_DIR        Overrides .storage/."
    echo "  LOG_DIR                    Overrides logs/."
    echo "  Create scripts/env.sh from scripts/env.sh.example for persistent overrides."
}

# Dispatch helper: look up <name> in COMMANDS and echo its handler.
_resolve_cmd() {
    local want=$1 row name handler _
    for row in "${COMMANDS[@]}"; do
        IFS='|' read -r name handler _ <<< "$row"
        if [ "$name" = "$want" ]; then
            echo "$handler"
            return 0
        fi
    done
    return 1
}

# -----------------------------------------------------------------------------
# Commands
# -----------------------------------------------------------------------------

do_setup() {
    local CI_MODE=${1:-false}
    local TOOL_BIN="$ROOT_DIR/.tools/bin"
    mkdir -p "$TOOL_BIN"
    export PATH="$TOOL_BIN:$(go env GOPATH)/bin:$PATH"

    if [ "$CI_MODE" = false ]; then
        _install_system_packages
        load_nvm || true
    fi

    _install_protoc "$TOOL_BIN"

    log_info "Installing Go plugins and linters..."
    ensure_go_tool "protoc-gen-go" \
        "google.golang.org/protobuf/cmd/protoc-gen-go@$PROTOC_GEN_GO_VERSION" \
        "${PROTOC_GEN_GO_VERSION#v}"
    ensure_go_tool "protoc-gen-go-grpc" \
        "google.golang.org/grpc/cmd/protoc-gen-go-grpc@$PROTOC_GEN_GO_GRPC_VERSION" \
        "${PROTOC_GEN_GO_GRPC_VERSION#v}"
    _install_golangci_lint "$TOOL_BIN"

    log_success "Setup completed."
    echo "Add $TOOL_BIN and $(go env GOPATH)/bin to your PATH."
}

_install_system_packages() {
    local CHECK_PACKAGES=(unzip libcap-dev curl python3 iproute2 sudo build-essential busybox)
    local PKG_MANAGER=""
    if   command -v apt-get &>/dev/null; then PKG_MANAGER="apt"
    elif command -v pacman  &>/dev/null; then PKG_MANAGER="pacman"
    elif command -v dnf     &>/dev/null; then PKG_MANAGER="dnf"
    fi

    local MISSING_PACKAGES=()
    local pkg installed
    for pkg in "${CHECK_PACKAGES[@]}"; do
        installed=false
        case "$PKG_MANAGER" in
            apt)    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed" && installed=true ;;
            pacman) pacman -Qi "$pkg" &>/dev/null && installed=true ;;
            dnf)    rpm -q "$pkg" &>/dev/null && installed=true ;;
            *)      command -v "$pkg" &>/dev/null && installed=true ;;
        esac
        [ "$installed" = false ] && MISSING_PACKAGES+=("$pkg")
    done

    [ ${#MISSING_PACKAGES[@]} -eq 0 ] && { log_info "System packages: all present."; return; }

    log_warn "Installing missing packages: ${MISSING_PACKAGES[*]}"
    local SUDO=""
    command -v sudo &> /dev/null && SUDO="sudo"
    case "$PKG_MANAGER" in
        apt)    $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -qq \
                && $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "${MISSING_PACKAGES[@]}" ;;
        pacman) $SUDO pacman -S --noconfirm "${MISSING_PACKAGES[@]}" ;;
        dnf)    $SUDO dnf install -y "${MISSING_PACKAGES[@]}" ;;
        *)      log_error "Unsupported package manager. Please install: ${MISSING_PACKAGES[*]}" ;;
    esac
}

_install_protoc() {
    local tool_bin=$1
    if command -v protoc &> /dev/null && protoc --version 2>/dev/null | grep -q "$PROTOC_VERSION"; then
        log_info "protoc already at $PROTOC_VERSION."
        return 0
    fi
    log_info "Installing protoc $PROTOC_VERSION to $tool_bin..."
    local arch
    arch=$(uname -m | sed 's/x86_64/x86_64/;s/aarch64/aarch_64/')
    local zip="protoc-$PROTOC_VERSION-linux-${arch}.zip"
    curl -sSLO "https://github.com/protocolbuffers/protobuf/releases/download/v$PROTOC_VERSION/$zip"
    unzip -o -q "$zip" -d "$ROOT_DIR/.tools" bin/protoc 'include/*'
    rm -f "$zip"
}

_install_golangci_lint() {
    local tool_bin=$1
    if command -v golangci-lint &> /dev/null \
        && golangci-lint --version 2>&1 | head -n1 | grep -q "${GOLANGCI_LINT_VERSION#v}"; then
        log_info "golangci-lint already at ${GOLANGCI_LINT_VERSION}."
        return 0
    fi
    log_info "Installing golangci-lint ${GOLANGCI_LINT_VERSION}..."
    curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \
        | sh -s -- -b "$tool_bin" "${GOLANGCI_LINT_VERSION}"
}

do_proto() {
    log_info "Generating Proto code..."
    mkdir -p internal/api/pb
    protoc --go_out=internal/api/pb --go_opt=paths=source_relative \
           --go-grpc_out=internal/api/pb --go-grpc_opt=paths=source_relative \
           -I api/proto api/proto/picobox.proto
    log_success "Proto code generated."
}

do_build() {
    log_info "Building PicoBox Components..."
    do_proto

    mkdir -p "$BIN_DIR"
    go build -o "$PICOBOXD_BIN"       ./cmd/picoboxd
    go build -o "$PICOBOX_MASTER_BIN" ./cmd/picobox-master
    log_success "Go binaries built."

    if [ -d "web" ] && [ -f "web/package.json" ]; then
        log_info "Building Web Dashboard..."
        (cd web && npm ci && npm run build)
        log_success "Web build completed."
    fi
}

do_release() {
    log_info "Building Production Release..."
    rm -rf "$BIN_DIR"
    mkdir -p "$BIN_DIR"

    do_proto

    local VERSION COMMIT DATE LDFLAGS
    VERSION="${PICOBOX_VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"
    COMMIT="${PICOBOX_COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}"
    DATE="${PICOBOX_BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    LDFLAGS="-s -w -X main.Version=${VERSION} -X main.Commit=${COMMIT} -X main.BuildDate=${DATE}"

    export CGO_ENABLED=0
    go build -trimpath -ldflags="${LDFLAGS}" -o "$PICOBOXD_BIN"       ./cmd/picoboxd
    go build -trimpath -ldflags="${LDFLAGS}" -o "$PICOBOX_MASTER_BIN" ./cmd/picobox-master
    log_success "Stripped Go binaries built (version=${VERSION}, commit=${COMMIT})."

    if [ -d "web" ]; then
        (cd web && npm ci && npm run build)
        log_success "Production Web build completed."
    fi

    (cd "$BIN_DIR" && sha256sum * > checksums.txt)
    log_success "Checksums written to $BIN_DIR/checksums.txt"
}

do_test() {
    local MODE=${1:-unit}
    case "$MODE" in
        regression)
            log_info "Running full regression suite (lint -> unit -> e2e)..."
            do_lint
            do_test unit
            do_e2e
            log_success "Full regression suite passed."
            ;;
        local)
            log_info "Running local CI simulation (act)..."
            command -v act &> /dev/null || log_error "'act' not installed. https://github.com/nektos/act"
            act -j lint -j test --container-options "--privileged"
            ;;
        unit)
            log_info "Running unit tests..."
            CGO_ENABLED=1 go test -race ./...
            if [ -d "web" ]; then
                log_info "Running Web tests..."
                (cd web && { [ -d node_modules ] || npm ci; } && npm test)
            fi
            ;;
        *)
            log_error "Unknown test mode: $MODE. Use unit | regression | local."
            ;;
    esac
}

do_e2e() {
    # Delegate to the standalone script so both `task.sh e2e` and
    # `./scripts/e2e.sh` behave identically.
    exec "$_TASK_SH_DIR/e2e.sh" "$@"
}

do_ci() {
    # Mirror the CI pipeline's fast feedback path so `task.sh ci` locally
    # is the same contract as PR checks (minus the privileged E2E job).
    log_info "Running local CI gate: fmt:check -> lint -> test unit"
    do_fmt_check
    do_lint
    do_test unit
    log_success "Local CI gate passed."
}

do_run() {
    log_info "Starting Full-Stack PicoBox Environment..."
    do_stop

    local p
    for p in 50051 3000 3001; do
        port_in_use "$p" && log_error "Port $p already in use. Free it before running."
    done

    _ensure_runtime_binaries
    "$_TASK_SH_DIR/prepare-rootfs.sh" > /dev/null

    export PICOBOX_API_TOKEN="${PICOBOX_API_TOKEN:-dev-secret-token}"
    log_info "Launching Master Server (gRPC :50051, REST :3000)..."
    "$PICOBOX_MASTER_BIN" > "$LOG_DIR/master.log" 2>&1 &
    save_pid master $!
    wait_for_port 127.0.0.1 50051
    wait_for_port 127.0.0.1 3000

    log_info "Launching PicoBox Agent..."
    "$PICOBOXD_BIN" > "$LOG_DIR/agent.log" 2>&1 &
    save_pid agent $!

    log_info "Launching Web Dashboard (:3001)..."
    (cd web && exec npm run dev) > "$LOG_DIR/web.log" 2>&1 &
    save_pid web $!
    wait_for_port 127.0.0.1 3001 30

    log_success "All services up."
    echo -e "${BOLD_WHITE}Dashboard:${NC} ${BLUE}http://localhost:3001${NC}"
    echo -e "${BOLD_WHITE}API:${NC}       ${BLUE}http://localhost:3000${NC}"
    echo -e "${BOLD_WHITE}Logs:${NC}      ${CYAN}./scripts/task.sh logs${NC}"

    command -v xdg-open &> /dev/null && xdg-open "http://localhost:3001" &> /dev/null &

    trap 'log_info "Shutting down..."; do_stop; exit 0' SIGINT SIGTERM

    log_info "Monitoring processes (Ctrl+C to stop)..."
    while true; do
        [ -s "$LOG_DIR/master.pid" ] && kill -0 "$(cat "$LOG_DIR/master.pid")" 2>/dev/null \
            || { log_warn "Master server died."; break; }
        [ -s "$LOG_DIR/agent.pid" ]  && kill -0 "$(cat "$LOG_DIR/agent.pid")"  2>/dev/null \
            || { log_warn "Agent died."; break; }
        sleep 5
    done
    do_stop
}

do_stop() {
    log_info "Stopping processes..."
    stop_pid_file web
    stop_pid_file agent
    stop_pid_file master
    stop_pid_file master_e2e
    stop_pid_file agent_e2e
    # Fallback: any residual Next.js dev servers spawned under different PIDs.
    pkill -f "next-server" 2>/dev/null || true
    log_success "All stopped."
}

_ensure_runtime_binaries() {
    ensure_go
    [ -x "$PICOBOXD_BIN" ] && [ -x "$PICOBOX_MASTER_BIN" ] \
        || log_warn "Binaries missing or stale. Consider './scripts/task.sh build'."
}

do_logs() {
    local SERVICE=${1:-all}
    local LINES=${2:-50}

    if [ "$SERVICE" = "clear" ]; then
        log_info "Clearing all logs in $LOG_DIR..."
        rm -f "$LOG_DIR"/*.log
        log_success "Logs cleared."
        return
    fi

    local files=()
    case "$SERVICE" in
        master) files=("$LOG_DIR/master.log") ;;
        agent)  files=("$LOG_DIR/agent.log") ;;
        web)    files=("$LOG_DIR/web.log") ;;
        all)
            shopt -s nullglob
            files=("$LOG_DIR"/*.log)
            shopt -u nullglob
            ;;
        *) log_error "Unknown service: $SERVICE. Use master|agent|web|all|clear." ;;
    esac

    [ ${#files[@]} -eq 0 ] && { log_warn "No log files in $LOG_DIR yet."; return; }

    log_info "Tailing last $LINES lines of ${#files[@]} file(s) — Ctrl+C to exit."
    exec tail -n "$LINES" -F "${files[@]}"
}

do_doctor() {
    log_info "Diagnosing PicoBox environment..."
    local ERRORS=0

    log_info "--- Kernel & Cgroups ---"
    log_info "Kernel: $(uname -r)"
    if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
        log_success "Cgroups v2 enabled."
    else
        log_warn "Cgroups v2 NOT detected."; ERRORS=$((ERRORS+1))
    fi
    if grep -q "overlay" /proc/filesystems; then
        log_success "OverlayFS supported."
    else
        log_warn "OverlayFS NOT supported."; ERRORS=$((ERRORS+1))
    fi

    log_info "--- Privileges ---"
    if [ "$EUID" -ne 0 ]; then
        log_warn "Not running as root. Namespaces/mount work will fail outside sudo."
    else
        log_success "Running with root privileges."
    fi

    log_info "--- Toolchain (pinned versions from versions.sh) ---"
    check_command "go"             "version"   "$GO_VERSION"             && log_success "Go $GO_VERSION"                   || log_warn "Go version mismatch or missing."
    check_command "node"           "-v"        "$NODE_VERSION"           && log_success "Node $NODE_VERSION"               || log_warn "Node version mismatch or missing."
    check_command "protoc"         "--version" "$PROTOC_VERSION"         && log_success "Protoc $PROTOC_VERSION"           || log_warn "Protoc version mismatch or missing."
    check_command "golangci-lint"  "--version" "${GOLANGCI_LINT_VERSION#v}" && log_success "golangci-lint ${GOLANGCI_LINT_VERSION}" || log_warn "golangci-lint missing."

    log_info "--- Binaries ---"
    [ -f "$PICOBOXD_BIN" ]       && log_success "Agent binary: Found"  || log_warn "Agent binary: Missing — run 'task.sh build'."
    [ -f "$PICOBOX_MASTER_BIN" ] && log_success "Master binary: Found" || log_warn "Master binary: Missing — run 'task.sh build'."

    log_info "--- Runtime Dependencies ---"
    command -v busybox &> /dev/null && log_success "busybox present" || log_warn "busybox missing (prepare-rootfs.sh requires it)"
    command -v ss      &> /dev/null && log_success "ss present"      || log_warn "ss missing (iproute2; used for port checks)"
    command -v curl    &> /dev/null && log_success "curl present"    || log_warn "curl missing (E2E HTTP tests)"
    command -v sudo    &> /dev/null && log_success "sudo present"    || log_warn "sudo missing (root needed for agent)"

    if command -v python3 &> /dev/null; then
        log_success "python3 present"
        python3 -c "import websockets" 2>/dev/null \
            && log_success "python3 websockets module present" \
            || log_warn "python3 websockets module missing — 'pip install --user websockets' (WS E2E will be skipped)"
    else
        log_warn "python3 missing (WS E2E will be skipped)"
    fi

    log_info "--- Cgroup Delegation ---"
    if [ -f "/sys/fs/cgroup/cgroup.subtree_control" ] \
        && grep -qE "(^| )(cpu|memory|pids)( |$)" /sys/fs/cgroup/cgroup.subtree_control; then
        log_success "cpu/memory/pids controllers delegated at cgroup root."
    else
        log_warn "Cgroup v2 controllers not delegated at root. Agent may fail to create cgroups."
    fi

    if [ "$ERRORS" -eq 0 ]; then
        log_success "Doctor found no critical issues."
    else
        log_error "Doctor found $ERRORS critical issues."
    fi
}

do_tidy() {
    log_info "Tidying Go modules..."
    go mod tidy
    log_success "Tidy completed."
}

# Internal: files gofmt should consider (exclude generated + web assets).
_go_source_files() {
    find . -type f -name '*.go' \
        -not -path './web/*' \
        -not -path './internal/api/pb/*'
}

do_fmt() {
    log_info "Formatting Go sources..."
    gofmt -w $(_go_source_files)
    log_info "Trimming trailing whitespace (shell/markdown only)..."
    find "$ROOT_DIR" -type f \( -name '*.sh' -o -name '*.md' \) \
        -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/.next/*" \
        -exec sed -i 's/[[:space:]]*$//' {} +
    log_success "Formatting applied."
}

do_fmt_check() {
    log_info "Checking Go formatting..."
    local drift
    drift=$(gofmt -l $(_go_source_files))
    if [ -n "$drift" ]; then
        log_warn "The following files are not gofmt-clean:"
        echo "$drift"
        log_error "Run './scripts/task.sh fmt' to fix."
    fi
    log_success "Formatting clean."
}

do_lint() {
    log_info "Running golangci-lint..."
    command -v golangci-lint &> /dev/null || log_error "golangci-lint missing. Run './scripts/task.sh setup'."
    golangci-lint run ./...
    log_success "Linting completed."
}

do_clean() {
    log_info "Cleaning build artifacts..."
    rm -rf "$BIN_DIR" logs/ web/.next web/node_modules
    log_success "Cleaned build outputs."
}

do_clean_data() {
    if [ ! -d "$PICOBOX_STORAGE_DIR" ]; then
        log_info "No storage directory to remove."
        return 0
    fi
    log_warn "About to remove runtime storage at $PICOBOX_STORAGE_DIR"
    log_warn "This is destructive and may require sudo for root-owned files."
    [ "${PICOBOX_CONFIRM_CLEAN_DATA:-}" = "yes" ] \
        || log_error "Set PICOBOX_CONFIRM_CLEAN_DATA=yes to proceed."
    local SUDO=""
    command -v sudo &> /dev/null && SUDO="sudo"
    $SUDO rm -rf "$PICOBOX_STORAGE_DIR"
    log_success "Storage directory removed."
}

# -----------------------------------------------------------------------------
# Router
# -----------------------------------------------------------------------------
CMD="${1:-help}"
shift || true

if [ "$CMD" = "-h" ] || [ "$CMD" = "--help" ] || [ "$CMD" = "help" ]; then
    print_usage
    exit 0
fi

handler=""
if ! handler=$(_resolve_cmd "$CMD"); then
    log_warn "Unknown command: $CMD"
    print_usage
    exit 1
fi

"$handler" "$@"
