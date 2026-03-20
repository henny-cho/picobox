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

set -e

# 0. Load Environment & Utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/versions.sh"

# Global Variables
export PICOBOX_STORAGE_DIR="$ROOT_DIR/storage"
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
    echo -e "  ${CYAN}test [mode]${NC}     Run test suites. Modes: ${GREEN}unit${NC} (default), ${GREEN}e2e${NC}, ${GREEN}local${NC} (act)."
    echo -e "  ${CYAN}e2e${NC}             Shortcut for running the full-stack E2E verification loop."
    echo -e "  ${CYAN}run${NC}             Start Master, Agent, and Web Dashboard in development mode."
    echo -e "  ${CYAN}stop${NC}            Stop all background PicoBox processes."
    echo -e "  ${CYAN}doctor${NC}          Verify system environment (Kernel, Cgroups, Root)."
    echo -e "  ${CYAN}logs [service]${NC}  Show logs for all or specific service (master, agent, web)."
    echo -e "  ${CYAN}release${NC}         Build production-ready binaries and web bundle."
    echo -e "  ${CYAN}clean${NC}           Remove build artifacts, logs, and temporary storage."
    echo -e "  ${CYAN}tidy${NC}            Run 'go mod tidy' for dependency management."
    echo -e "  ${CYAN}lint${NC}            Run 'golangci-lint' to ensure code quality.\n"
    echo -e "${BOLD_WHITE}EXAMPLES:${NC}"
    echo -e "  ./scripts/task.sh setup           # Fresh setup"
    echo -e "  ./scripts/task.sh build           # Full rebuild"
    echo -e "  ./scripts/task.sh test e2e        # Run integration tests"
    echo -e "  ./scripts/task.sh run             # Start dev environment"
}

# --- Commands ---

do_setup() {
    local CI_MODE=${1:-false}
    local TOOL_BIN="$ROOT_DIR/.tools/bin"
    mkdir -p "$TOOL_BIN"
    export PATH="$TOOL_BIN:$(go env GOPATH)/bin:$PATH"

    log_info "Step 1: System dependencies..."
    if [ "$CI_MODE" = false ]; then
        CHECK_PACKAGES=(unzip libcap-dev curl python3 iproute2 sudo build-essential)
        MISSING_PACKAGES=()
        for pkg in "${CHECK_PACKAGES[@]}"; do
            if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
                MISSING_PACKAGES+=("$pkg")
            fi
        done

        if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
            log_warn "Installing missing packages: ${MISSING_PACKAGES[*]}"
            SUDO="" && command -v sudo &> /dev/null && SUDO="sudo"
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -qq && $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "${MISSING_PACKAGES[@]}"
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
    go install google.golang.org/protobuf/cmd/protoc-gen-go@$PROTOC_GEN_GO_VERSION
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@$PROTOC_GEN_GO_GRPC_VERSION
    if ! command -v golangci-lint &> /dev/null; then
        curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b "$TOOL_BIN" "${GOLANGCI_LINT_VERSION}"
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

do_build() {
    log_info "Building PicoBox Components..."
    do_tidy
    format_code

    # 1. Proto
    log_info "Generating Proto code..."
    mkdir -p internal/api/pb
    protoc --go_out=internal/api/pb --go_opt=paths=source_relative \
           --go-grpc_out=internal/api/pb --go-grpc_opt=paths=source_relative \
           -I api/proto api/proto/picobox.proto
    log_success "Proto code generated."

    # 2. Go Binaries
    mkdir -p "$BIN_DIR"
    go build -o "$PICOBOXD_BIN" ./cmd/picoboxd
    go build -o "$PICOBOX_MASTER_BIN" ./cmd/picobox-master
    log_success "Go binaries built."

    # 3. Web (Optional check)
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
    log_info "Starting E2E Runtime Tests..."
    do_stop
    do_build # Ensure fresh binaries
    ./scripts/prepare-rootfs.sh > /dev/null

    $PICOBOX_MASTER_BIN > "$LOG_DIR/master_e2e.log" 2>&1 &
    local MASTER_PID=$!
    wait_for_port 127.0.0.1 50051

    $PICOBOXD_BIN > "$LOG_DIR/agent_e2e.log" 2>&1 &
    local AGENT_PID=$!

    trap "stop_process $MASTER_PID; stop_process $AGENT_PID; [ -f \"$LOG_DIR/agent_e2e.log\" ] && cat \"$LOG_DIR/agent_e2e.log\"" EXIT
    log_info "Waiting for Agent to register..."
    sleep 10

    # Trigger deployment via curl
    ROOTFS_PATH="$PICOBOX_STORAGE_DIR/rootfs/busybox"
    curl -s -X POST http://localhost:3000/api/deploy \
         -H "Content-Type: application/json" \
         -d "{\"hostname\": \"$(hostname)\", \"container_id\": \"test\", \"rootfs_image_url\": \"$ROOTFS_PATH\", \"command\": \"/bin/sh\"}"

    log_info "Verifying..."
    sleep 5
    if grep -q "Container .* started" "$LOG_DIR/agent_e2e.log"; then
        log_success "E2E Test Passed!"
    else
        log_error "E2E Test Failed! Agent log check:"
        cat "$LOG_DIR/agent_e2e.log"
        exit 1
    fi
}

do_run() {
    log_info "Starting Full-Stack..."
    do_stop
    
    # Check for port availability
    if netstat -tuln | grep -E ":50051 |:3000 " > /dev/null; then
        log_error "Port 50051 or 3000 is still in use. Please check with 'lsof -i'."
        exit 1
    fi

    [ ! -f "$PICOBOXD_BIN" ] && do_build
    ./scripts/prepare-rootfs.sh > /dev/null

    $PICOBOX_MASTER_BIN > "$LOG_DIR/master.log" 2>&1 &
    local MASTER_PID=$!
    wait_for_port 127.0.0.1 50051

    $PICOBOXD_BIN > "$LOG_DIR/agent.log" 2>&1 &
    local DAEMON_PID=$!

    (cd web && npm run dev) > "$LOG_DIR/web.log" 2>&1 &
    local WEB_PID=$!

    log_success "Services running. Press Ctrl+C to stop."
    trap "do_stop; exit 0" SIGINT SIGTERM
    wait
}

do_stop() {
    log_info "Stopping processes..."
    stop_process "picobox-master"
    stop_process "picoboxd"
    # For web dev server, it might be harder to pkill if not known
    pkill -f "next-dev" || true
    log_success "All stopped."
}

do_doctor() {
    log_info "Diagnosing PicoBox Environment..."
    local ERRORS=0

    # 1. Kernel Version
    local KERNEL=$(uname -r | cut -d. -f1,2)
    log_info "Kernel: $(uname -r)"
    if (( $(echo "$KERNEL < 5.10" | bc -l) )); then
        log_warn "Kernel version < 5.10 might have limited Cgroups v2 support."
    fi

    # 2. Cgroups v2 checking controllers
    if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
        log_success "Cgroups v2 is enabled. Controllers: $(cat /sys/fs/cgroup/cgroup.controllers)"
    else
        log_error "Cgroups v2 is not detected. Ensure systemd.unified_cgroup_hierarchy=1."
        ERRORS=$((ERRORS+1))
    fi

    # 2.1 OverlayFS Support
    if grep -q "overlay" /proc/filesystems; then
        log_success "OverlayFS support detected in kernel."
    else
        log_error "OverlayFS NOT detected. RootFS layering will fail."
        ERRORS=$((ERRORS+1))
    fi

    # 3. Privileges
    if [ "$EUID" -ne 0 ]; then
        log_warn "Not running as root. Container features (Mount, PivotRoot) will fail."
        log_info "Recommendation: Run with 'sudo ./scripts/task.sh run' or 'sudo ./scripts/task.sh e2e'."
    else
        log_success "Running with root privileges."
    fi

    # 4. Dependency checks
    log_info "Tools: Go $(go version | awk '{print $3}'), Node $(node -v 2>/dev/null || echo 'N/A'), NPM $(npm -v 2>/dev/null || echo 'N/A')"
    [ ! -f "$PICOBOXD_BIN" ] && log_warn "Agent binary missing. Run './scripts/task.sh build'."
    [ ! -f "$PICOBOX_MASTER_BIN" ] && log_warn "Master binary missing. Run './scripts/task.sh build'."

    if [ $ERRORS -eq 0 ]; then
        log_success "Doctor found no critical issues."
    else
        log_error "Doctor found $ERRORS critical issues."
    fi
}

do_logs() {
    local SERVICE=${1:-"all"}
    local LINES=${2:-"50"}
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
    do_clean
    # 1. Build optimized Go binaries
    mkdir -p "$BIN_DIR"
    export CGO_ENABLED=0
    go build -ldflags="-s -w" -o "$PICOBOXD_BIN" ./cmd/picoboxd
    go build -ldflags="-s -w" -o "$PICOBOX_MASTER_BIN" ./cmd/picobox-master
    log_success "Stripped Go binaries built."

    # 2. Build production Web
    if [ -d "web" ]; then
        (cd web && npm ci && npm run build)
        log_success "Production Web build completed."
    fi
}

do_clean() {
    log_info "Cleaning..."
    rm -rf bin/ logs/ storage/ web/.next web/node_modules
    log_success "Cleaned."
}

# --- Router ---

case "$1" in
    setup)  do_setup "${2:-false}" ;;
    build)  do_build ;;
    test)   do_test "${2:-unit}" ;;
    e2e)    do_e2e ;;
    run)    do_run ;;
    stop)   do_stop ;;
    doctor) do_doctor ;;
    logs)   do_logs "$2" "$3" ;;
    release) do_release ;;
    clean)  do_clean ;;
    tidy)   do_tidy ;;
    lint)   do_lint ;;
    -h|--help|"") print_usage ;;
    *)      print_usage; exit 1 ;;
esac
