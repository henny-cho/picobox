#!/usr/bin/env bash
# PicoBox Unified Task Runner
# -----------------------------------------------------------------------------
# This script centralizes all development, build, and test automation for PicoBox.
# It ensures consistency across local and CI environments by managing toolchains
# and orchestrating complex multi-service workflows.
#
# Main Features:
# - Environment Setup (Go, Node, Protoc, golangci-lint)
# - Monorepo Build (Go Binaries, Protobuf, Next.js Dashboard)
# - Comprehensive Testing (Unit, Integration, E2E, Local CI Simulation)
# - Full-Stack Local Execution (Master, Agent, Web)
#
# Usage:
#   ./scripts/task.sh [command] [options]
#
# Examples:
#   ./scripts/task.sh setup         # Initialize local environment
#   ./scripts/task.sh build         # Compile all components
#   ./scripts/task.sh test unit     # Run unit tests
#   ./scripts/task.sh run           # Start development stack
# -----------------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

# 0. Load Environment & Utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/versions.sh"

# Add local tools and Go binaries to PATH
export PATH="$ROOT_DIR/.tools/bin:$(go env GOPATH)/bin:$PATH"

# Global Variables
export PICOBOX_STORAGE_DIR="$ROOT_DIR/.storage"
export LOG_DIR="$ROOT_DIR/logs"

mkdir -p "$LOG_DIR" "$PICOBOX_STORAGE_DIR"

# --- Utilities ---

print_usage() {
    echo -e "${BOLD_CYAN}PicoBox Task Runner${NC}"
    echo -e "Usage: ./scripts/task.sh [command] [options]\n"
    echo -e "${BOLD_WHITE}COMMANDS:${NC}"
    echo -e "  ${CYAN}setup [ci]${NC}      Install system dependencies, toolchains, and plugins."
    echo -e "                    Use 'ci' flag in automated environments."
    echo -e "  ${CYAN}build${NC}           Generate Proto code and build Go & Web binaries."
    echo -e "  ${CYAN}test [mode]${NC}     Run test suites. Modes: ${GREEN}unit${NC} (default), ${GREEN}e2e${NC}, ${GREEN}regression${NC}, ${GREEN}local${NC} (act)."
    echo -e "  ${CYAN}e2e${NC}             Shortcut for running the full-stack E2E verification loop."
    echo -e "  ${CYAN}run${NC}             Start Master, Agent, and Web Dashboard in development mode."
    echo -e "  ${CYAN}stop${NC}            Stop all background PicoBox processes."
    echo -e "  ${CYAN}doctor${NC}          Verify system environment (Kernel, Cgroups, Root, Tools)."
    echo -e "  ${CYAN}logs [service]${NC}  Show logs for all or specific service (master, agent, web)."
    echo -e "                    Use 'clear' to remove all log files."
    echo -e "  ${CYAN}release${NC}         Build production-ready binaries and web bundle."
    echo -e "  ${CYAN}clean${NC}           Remove build artifacts and logs (bin/, web/.next, logs/)."
    echo -e "  ${CYAN}clean:data${NC}      Remove runtime storage (.storage/). Destructive, requires sudo."
    echo -e "  ${CYAN}tidy${NC}            Run 'go mod tidy' for dependency management."
    echo -e "  ${CYAN}fmt${NC}             Apply gofmt and trim trailing whitespace (in-place)."
    echo -e "  ${CYAN}fmt:check${NC}       Verify formatting without modifying files (CI mode)."
    echo -e "  ${CYAN}lint${NC}            Run 'golangci-lint' to ensure code quality.\n"
    echo -e "${BOLD_WHITE}EXAMPLES:${NC}"
    echo -e "  ./scripts/task.sh setup           # Fresh setup"
    echo -e "  ./scripts/task.sh build           # Full rebuild"
    echo -e "  ./scripts/task.sh test e2e        # Run integration tests"
    echo -e "  ./scripts/task.sh run             # Start dev environment"
}

do_check_deps() {
    local cmd=$1
    case "$cmd" in
        build|test|release|lint)
            ensure_go
            check_command "protoc" "--version" "$PROTOC_VERSION" || log_warn "protoc $PROTOC_VERSION not found. Run 'task.sh setup'."
            ;;
        run|e2e)
            ensure_go
            [ ! -f "$PICOBOXD_BIN" ] || [ ! -f "$PICOBOX_MASTER_BIN" ] && log_warn "Binaries missing. Run 'task.sh build'."
            ;;
    esac
    return 0
}

# --- Commands ---

do_setup() {
    local CI_MODE=${1:-false}
    local TOOL_BIN="$ROOT_DIR/.tools/bin"
    mkdir -p "$TOOL_BIN"
    export PATH="$TOOL_BIN:$(go env GOPATH)/bin:$PATH"

    log_info "Step 1: System dependencies..."
    if [ "$CI_MODE" = false ]; then
        CHECK_PACKAGES=(unzip libcap-dev curl python3 iproute2 sudo build-essential busybox)
        MISSING_PACKAGES=()

        # Detect Package Manager
        local PKG_MANAGER=""
        if command -v apt-get &>/dev/null; then PKG_MANAGER="apt";
        elif command -v pacman &>/dev/null; then PKG_MANAGER="pacman";
        elif command -v dnf &>/dev/null; then PKG_MANAGER="dnf";
        fi

        for pkg in "${CHECK_PACKAGES[@]}"; do
            local installed=false
            case "$PKG_MANAGER" in
                apt) dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed" && installed=true ;;
                pacman) pacman -Qi "$pkg" &>/dev/null && installed=true ;;
                dnf) rpm -q "$pkg" &>/dev/null && installed=true ;;
                *) # Generic fallback
                   command -v "$pkg" &>/dev/null && installed=true
                   ;;
            esac
            [ "$installed" = false ] && MISSING_PACKAGES+=("$pkg")
        done

        if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
            log_warn "Installing missing packages: ${MISSING_PACKAGES[*]}"
            SUDO="" && command -v sudo &> /dev/null && SUDO="sudo"
            case "$PKG_MANAGER" in
                apt) $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -qq && $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "${MISSING_PACKAGES[@]}" ;;
                pacman) $SUDO pacman -S --noconfirm "${MISSING_PACKAGES[@]}" ;;
                dnf) $SUDO dnf install -y "${MISSING_PACKAGES[@]}" ;;
                *) log_error "Unsupported package manager. Please install: ${MISSING_PACKAGES[*]}" ;;
            esac
        fi
    fi

    log_info "Step 2: Toolchains (Go, Node, Protoc)..."
    if [ "$CI_MODE" = false ]; then
        load_nvm || true
    fi

    # Protoc Installation (to $TOOL_BIN)
    if ! command -v protoc &> /dev/null || [[ $(protoc --version) != *"$PROTOC_VERSION"* ]]; then
        log_info "Installing protoc $PROTOC_VERSION to $TOOL_BIN..."
        PROTOC_ZIP="protoc-$PROTOC_VERSION-linux-$(uname -m | sed 's/x86_64/x86_64/' | sed 's/aarch64/aarch_64/').zip"
        curl -sSLO "https://github.com/protocolbuffers/protobuf/releases/download/v$PROTOC_VERSION/$PROTOC_ZIP"
        unzip -o -q "$PROTOC_ZIP" -d "$ROOT_DIR/.tools" bin/protoc 'include/*' && rm -f "$PROTOC_ZIP"
    fi

    log_info "Step 3: Go Plugins & Linters..."
    ensure_go_tool "protoc-gen-go" \
        "google.golang.org/protobuf/cmd/protoc-gen-go@$PROTOC_GEN_GO_VERSION" \
        "${PROTOC_GEN_GO_VERSION#v}"
    ensure_go_tool "protoc-gen-go-grpc" \
        "google.golang.org/grpc/cmd/protoc-gen-go-grpc@$PROTOC_GEN_GO_GRPC_VERSION" \
        "${PROTOC_GEN_GO_GRPC_VERSION#v}"

    local current_lint=""
    if command -v golangci-lint &> /dev/null; then
        current_lint=$(golangci-lint --version 2>&1 | head -n1 || true)
    fi
    if ! echo "$current_lint" | grep -q "${GOLANGCI_LINT_VERSION#v}"; then
        log_info "Installing golangci-lint ${GOLANGCI_LINT_VERSION}..."
        curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \
            | sh -s -- -b "$TOOL_BIN" "${GOLANGCI_LINT_VERSION}"
    else
        log_info "golangci-lint already at ${GOLANGCI_LINT_VERSION}."
    fi

    log_success "Setup completed."
    echo "Please add $TOOL_BIN and $(go env GOPATH)/bin to your PATH."
}

do_tidy() {
    log_info "Tidying Go modules..."
    go mod tidy
    log_success "Tidy completed."
}

do_lint() {
    log_info "Running Go Linter (golangci-lint)..."
    if ! command -v golangci-lint &> /dev/null; then
        log_warn "golangci-lint not found. Running setup..."
        do_setup true
    fi
    golangci-lint run ./...
    log_success "Linting completed."
}

do_fmt() {
    log_info "Formatting Go sources (gofmt -w)..."
    gofmt -w $(find . -type f -name '*.go' \
        -not -path './web/*' \
        -not -path './internal/api/pb/*')
    format_code
    log_success "Formatting applied."
}

do_fmt_check() {
    log_info "Checking Go formatting (gofmt -l)..."
    local diff
    diff=$(gofmt -l $(find . -type f -name '*.go' \
        -not -path './web/*' \
        -not -path './internal/api/pb/*'))
    if [ -n "$diff" ]; then
        log_warn "The following files are not gofmt-clean:"
        echo "$diff"
        log_error "Run './scripts/task.sh fmt' to fix."
    fi
    log_success "Formatting clean."
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
    go build -o "$PICOBOXD_BIN" ./cmd/picoboxd
    go build -o "$PICOBOX_MASTER_BIN" ./cmd/picobox-master
    log_success "Go binaries built."

    if [ -d "web" ] && [ -f "web/package.json" ]; then
        log_info "Building Web Dashboard..."
        (cd web && npm ci && npm run build)
        log_success "Web build completed."
    fi
}

do_test() {
    local MODE=$1 # "unit", "e2e", or "local"
    case "$MODE" in
        e2e) do_e2e ;;
        regression)
            log_info "Running Full Regression Suite (Lint -> Unit -> E2E)..."
            do_lint || exit 1
            do_test unit || exit 1
            do_e2e || exit 1
            log_success "Full Regression Suite Passed!"
            ;;
        local)
            log_info "Running Local CI Simulation (act)..."
            if ! command -v act &> /dev/null; then
                log_error "'act' not installed. Visit https://github.com/nektos/act"
            fi
            act -j lint -j test --container-options "--privileged"
            ;;
        *)
            log_info "Running Unit Tests..."
            CGO_ENABLED=1 go test -v -race ./...
            if [ -d "web" ]; then
                log_info "Running Web Tests..."
                (cd web && [ ! -d "node_modules" ] && npm ci || true)
                (cd web && npm test)
            fi
            ;;
    esac
}

do_e2e() {
    local SKIP_BUILD=false
    local arg
    for arg in "$@"; do
        case "$arg" in
            --skip-build) SKIP_BUILD=true ;;
        esac
    done

    log_info "Starting E2E Runtime Tests..."
    do_stop

    if [ "$SKIP_BUILD" = false ]; then
        do_build
    else
        log_info "Skipping build (--skip-build). Verifying artifacts..."
        [ -x "$PICOBOXD_BIN" ] || log_error "Agent binary missing at $PICOBOXD_BIN"
        [ -x "$PICOBOX_MASTER_BIN" ] || log_error "Master binary missing at $PICOBOX_MASTER_BIN"
    fi
    ./scripts/prepare-rootfs.sh > /dev/null

    export PICOBOX_API_TOKEN="${PICOBOX_API_TOKEN:-e2e-secret-token}"

    "$PICOBOX_MASTER_BIN" > "$LOG_DIR/master_e2e.log" 2>&1 &
    local MASTER_PID=$!
    save_pid master_e2e "$MASTER_PID"
    wait_for_port 127.0.0.1 50051
    wait_for_port 127.0.0.1 3000

    "$PICOBOXD_BIN" > "$LOG_DIR/agent_e2e.log" 2>&1 &
    local AGENT_PID=$!
    save_pid agent_e2e "$AGENT_PID"

    cleanup_e2e() {
        local code=${1:-0}
        stop_pid_file master_e2e
        stop_pid_file agent_e2e
        if [ "$code" -ne 0 ]; then
            log_info "--- Agent Log (tail) ---"; tail -n 60 "$LOG_DIR/agent_e2e.log" 2>/dev/null || true
            log_info "--- Master Log (tail) ---"; tail -n 60 "$LOG_DIR/master_e2e.log" 2>/dev/null || true
        fi
    }
    trap 'cleanup_e2e $?' EXIT

    # Wait for agent → master registration via log signal (no hard sleep).
    wait_for_log "$LOG_DIR/master_e2e.log" "\[Master\] Received metrics from" 30 "agent registration" \
        || log_error "Agent did not register in time."

    # Test 0: Authentication Failure
    log_info "Testing Authentication Failure..."
    local HTTP_STATUS
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:3000/api/deploy \
         -H "Authorization: Bearer wrong-token" \
         -H "Content-Type: application/json" \
         -d "{}")
    if [ "$HTTP_STATUS" = "401" ]; then
        log_success "Auth Test Passed (Got 401 as expected)"
    else
        log_error "Auth Test Failed! Expected 401, got $HTTP_STATUS"
    fi

    # Test 1: Deploy + log streaming
    local ROOTFS_PATH="$PICOBOX_STORAGE_DIR/rootfs/busybox"
    curl -s -X POST http://localhost:3000/api/deploy \
         -H "Authorization: Bearer $PICOBOX_API_TOKEN" \
         -H "Content-Type: application/json" \
         -d "{\"hostname\": \"$(hostname)\", \"container_id\": \"test\", \"rootfs_image_url\": \"$ROOTFS_PATH\", \"command\": \"sh -c \\\"while true; do echo 'hello from container'; sleep 2; done\\\"\"}" \
         > /dev/null

    wait_for_log "$LOG_DIR/agent_e2e.log" "\[PicoBox-Agent\] Sandbox test active" 20 "sandbox active" \
        || log_error "Sandbox did not become active."
    wait_for_log "$LOG_DIR/master_e2e.log" "\[Master\] \[Log\] test: hello from container" 20 "log streaming" \
        || log_error "Log streaming did not reach master."
    log_success "E2E Test & Log Streaming Passed!"

    # Test 2: Automatic Scheduler (no hostname)
    log_info "Testing Automatic Scheduler (no hostname)..."
    curl -s -X POST http://localhost:3000/api/deploy \
         -H "Authorization: Bearer $PICOBOX_API_TOKEN" \
         -H "Content-Type: application/json" \
         -d "{\"container_id\": \"sched-test\", \"rootfs_image_url\": \"$ROOTFS_PATH\", \"command\": \"echo 'sched-ok'\"}" \
         > /dev/null

    wait_for_log "$LOG_DIR/master_e2e.log" "\[Scheduler\] Automatically selected node" 15 "scheduler decision" \
        || log_error "Scheduler did not auto-select."
    wait_for_log "$LOG_DIR/agent_e2e.log" "\[PicoBox-Agent\] Sandbox sched-test active" 15 "sched-test sandbox" \
        || log_error "Sandbox sched-test did not activate."
    log_success "Automatic Scheduler Test Passed!"

    # Test 3: Web Terminal (WebSocket)
    log_info "Testing Web Terminal (WebSocket)..."
    if ! command -v python3 >/dev/null 2>&1; then
        log_warn "python3 not available; skipping WebSocket test."
    elif ! python3 -c "import websockets" 2>/dev/null; then
        log_warn "python3-websockets not installed; skipping WebSocket test."
        log_warn "Install via: pip install --user websockets"
    else
        python3 -u - "$PICOBOX_API_TOKEN" <<'PY' > "$LOG_DIR/ws_test.log" 2>&1 || true
import asyncio, websockets, sys
token = sys.argv[1]
async def test_ws():
    uri = f'ws://localhost:3000/ws/terminal?container_id=test&token={token}'
    async with websockets.connect(uri) as ws:
        conn_msg = await ws.recv()
        print(f'Conn msg: {conn_msg.strip()}')
        await ws.send('echo WS_TEST_OK')
        response = await asyncio.wait_for(ws.recv(), timeout=5.0)
        print(f'Response: {response.strip()}')
        if 'WS_TEST_OK' in response:
            print('PASS')
            return
        print(f'FAIL: Unexpected response: {response}')
        sys.exit(1)
asyncio.run(test_ws())
PY
        if grep -q "PASS" "$LOG_DIR/ws_test.log"; then
            log_success "Web Terminal WebSocket Test Passed!"
        else
            cat "$LOG_DIR/ws_test.log"
            log_error "Web Terminal WebSocket Test Failed!"
        fi
    fi
}


do_run() {
    log_info "Starting Full-Stack PicoBox Environment..."
    do_stop

    # 1. Pre-flight port checks
    local p
    for p in 50051 3000 3001; do
        if port_in_use "$p"; then
            log_error "Port $p already in use. Free it before running."
        fi
    done

    do_check_deps run
    ./scripts/prepare-rootfs.sh > /dev/null

    # 2. Start Services
    export PICOBOX_API_TOKEN="${PICOBOX_API_TOKEN:-dev-secret-token}"
    log_info "Launching Master Server (Port 50051, 3000)..."
    "$PICOBOX_MASTER_BIN" > "$LOG_DIR/master.log" 2>&1 &
    local MASTER_PID=$!
    save_pid master "$MASTER_PID"
    wait_for_port 127.0.0.1 50051
    wait_for_port 127.0.0.1 3000

    log_info "Launching PicoBox Agent..."
    "$PICOBOXD_BIN" > "$LOG_DIR/agent.log" 2>&1 &
    local AGENT_PID=$!
    save_pid agent "$AGENT_PID"

    log_info "Launching Web Dashboard (Port 3001)..."
    (cd web && exec npm run dev) > "$LOG_DIR/web.log" 2>&1 &
    local WEB_PID=$!
    save_pid web "$WEB_PID"
    wait_for_port 127.0.0.1 3001 30

    log_success "All services are up and running!"
    echo -e "${BOLD_WHITE}Dashboard:${NC} ${BLUE}http://localhost:3001${NC}"
    echo -e "${BOLD_WHITE}API:${NC}       ${BLUE}http://localhost:3000${NC}"
    echo -e "${BOLD_WHITE}Logs:${NC}      ${CYAN}tail -f $LOG_DIR/*.log${NC}"

    if command -v xdg-open &> /dev/null; then
        xdg-open "http://localhost:3001" &> /dev/null &
    fi

    # 3. Signal handling
    trap "log_info 'Shutting down...'; do_stop; exit 0" SIGINT SIGTERM

    log_info "Monitoring processes (Press Ctrl+C to stop)..."
    while true; do
        kill -0 "$MASTER_PID" 2>/dev/null || { log_warn "Master server died."; break; }
        kill -0 "$AGENT_PID"  2>/dev/null || { log_warn "Agent died.";         break; }
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

do_doctor() {
    log_info "Diagnosing PicoBox Environment..."
    local ERRORS=0

    # 1. Kernel & Cgroups
    local KERNEL=$(uname -r | cut -d. -f1,2)
    log_info "Kernel: $(uname -r)"
    if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
        log_success "Cgroups v2 enabled."
    else
        log_error "Cgroups v2 NOT detected."
        ERRORS=$((ERRORS+1))
    fi

    if grep -q "overlay" /proc/filesystems; then
        log_success "OverlayFS supported."
    else
        log_error "OverlayFS NOT supported."
        ERRORS=$((ERRORS+1))
    fi

    # 2. Privileges
    [ "$EUID" -ne 0 ] && log_warn "Not running as root. Container features (Mount, PivotRoot) will fail." || log_success "Running with root privileges."

    # 3. Toolchain Checks
    log_info "--- Toolchain ---"
    check_command "go" "version" "$GO_VERSION" && log_success "Go $GO_VERSION" || log_warn "Go version mismatch or missing."
    check_command "node" "-v" "$NODE_VERSION" && log_success "Node $NODE_VERSION" || log_warn "Node version mismatch or missing."
    check_command "protoc" "--version" "$PROTOC_VERSION" && log_success "Protoc $PROTOC_VERSION" || log_warn "Protoc version mismatch or missing."
    check_command "golangci-lint" "--version" "$GOLANGCI_LINT_VERSION" && log_success "golangci-lint $GOLANGCI_LINT_VERSION" || log_warn "golangci-lint missing."

    # 4. Binary Checks
    log_info "--- Binaries ---"
    [ -f "$PICOBOXD_BIN" ] && log_success "Agent binary: Found" || log_warn "Agent binary: Missing"
    [ -f "$PICOBOX_MASTER_BIN" ] && log_success "Master binary: Found" || log_warn "Master binary: Missing"

    # 5. Runtime dependencies
    log_info "--- Runtime Dependencies ---"
    command -v busybox   &> /dev/null && log_success "busybox present" || log_warn "busybox missing (required by prepare-rootfs.sh)"
    command -v ss        &> /dev/null && log_success "ss present"      || log_warn "ss missing (iproute2; used for port checks)"
    command -v curl      &> /dev/null && log_success "curl present"    || log_warn "curl missing (required by E2E HTTP tests)"
    command -v sudo      &> /dev/null && log_success "sudo present"    || log_warn "sudo missing (agent needs root for mount/namespaces)"

    if command -v python3 &> /dev/null; then
        log_success "python3 present"
        if python3 -c "import websockets" 2>/dev/null; then
            log_success "python3 websockets module present"
        else
            log_warn "python3 websockets module missing (WS E2E will be skipped). Install: pip install --user websockets"
        fi
    else
        log_warn "python3 missing (WS E2E will be skipped)"
    fi

    # 6. Cgroup delegation (agent operates under /sys/fs/cgroup/picobox)
    if [ -f "/sys/fs/cgroup/cgroup.subtree_control" ]; then
        if grep -qE "(^| )(cpu|memory|pids)( |$)" /sys/fs/cgroup/cgroup.subtree_control; then
            log_success "Cgroup v2 controllers delegated (cpu/memory/pids available at root)."
        else
            log_warn "Cgroup v2 controllers not delegated at root. Agent may fail to create cgroups."
        fi
    fi

    if [ $ERRORS -eq 0 ]; then
        log_success "Doctor found no critical issues."
    else
        log_error "Doctor found $ERRORS critical issues."
    fi
}

do_logs() {
    local SERVICE=${1:-"all"}
    local LINES=${2:-"50"}

    if [ "$SERVICE" = "clear" ]; then
        log_info "Clearing all logs in $LOG_DIR..."
        rm -f "$LOG_DIR"/*.log
        log_success "Logs cleared."
        return
    fi

    log_info "Showing last $LINES logs for $SERVICE..."

    local LOG_FILE=""
    case "$SERVICE" in
        master) LOG_FILE="$LOG_DIR/master.log" ;;
        agent)  LOG_FILE="$LOG_DIR/agent.log" ;;
        web)    LOG_FILE="$LOG_DIR/web.log" ;;
        *)      LOG_FILE="$LOG_DIR"/*.log ;;
    esac

    for f in $LOG_FILE; do
        if [ -f "$f" ]; then
            tail -n "$LINES" -f "$f" &
        fi
    done
    wait
}

do_release() {
    log_info "Building Production Release..."
    # Only remove prior build outputs — never touch runtime data in release.
    rm -rf "$BIN_DIR"
    mkdir -p "$BIN_DIR"

    do_proto

    local VERSION COMMIT DATE LDFLAGS
    VERSION="${PICOBOX_VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo "dev")}"
    COMMIT="${PICOBOX_COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")}"
    DATE="${PICOBOX_BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    LDFLAGS="-s -w -X main.Version=${VERSION} -X main.Commit=${COMMIT} -X main.BuildDate=${DATE}"

    export CGO_ENABLED=0
    go build -trimpath -ldflags="${LDFLAGS}" -o "$PICOBOXD_BIN" ./cmd/picoboxd
    go build -trimpath -ldflags="${LDFLAGS}" -o "$PICOBOX_MASTER_BIN" ./cmd/picobox-master
    log_success "Stripped Go binaries built (version=${VERSION}, commit=${COMMIT})."

    if [ -d "web" ]; then
        (cd web && npm ci && npm run build)
        log_success "Production Web build completed."
    fi

    # Emit checksums for release artifacts.
    (cd "$BIN_DIR" && sha256sum * > checksums.txt)
    log_success "Checksums written to $BIN_DIR/checksums.txt"
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
    if [ "${PICOBOX_CONFIRM_CLEAN_DATA:-}" != "yes" ]; then
        log_error "Set PICOBOX_CONFIRM_CLEAN_DATA=yes to proceed."
    fi
    local SUDO=""
    command -v sudo &> /dev/null && SUDO="sudo"
    $SUDO rm -rf "$PICOBOX_STORAGE_DIR"
    log_success "Storage directory removed."
}

# --- Router ---

CMD="${1:-}"
case "$CMD" in
    setup)       do_setup "${2:-false}" ;;
    build)       do_build ;;
    proto)       do_proto ;;
    test)        do_test "${2:-unit}" ;;
    e2e)         shift || true; do_e2e "$@" ;;
    run)         do_run ;;
    stop)        do_stop ;;
    doctor)      do_doctor ;;
    logs)        do_logs "${2:-all}" "${3:-50}" ;;
    release)     do_release ;;
    clean)       do_clean ;;
    clean:data)  do_clean_data ;;
    tidy)        do_tidy ;;
    fmt)         do_fmt ;;
    fmt:check)   do_fmt_check ;;
    lint)        do_lint ;;
    -h|--help|"") print_usage ;;
    *)           print_usage; exit 1 ;;
esac
