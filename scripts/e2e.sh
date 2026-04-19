#!/usr/bin/env bash
# PicoBox E2E Runtime Verification
# -----------------------------------------------------------------------------
# Boots master + agent locally, runs a deploy/scheduler/WebSocket suite against
# them, and tears everything down. Designed to be invokable both directly
# (`./scripts/e2e.sh [--skip-build]`) and via the task runner
# (`./scripts/task.sh e2e`).
#
# Requires root for the agent's namespace/mount work. In CI the caller is
# expected to run `sudo -E ./scripts/e2e.sh --skip-build`.
# -----------------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

cd "$ROOT_DIR"
mkdir -p "$LOG_DIR" "$PICOBOX_STORAGE_DIR"

SKIP_BUILD=false
for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=true ;;
        -h|--help)
            cat <<EOF
Usage: $0 [--skip-build]

Options:
  --skip-build   Use the binaries already in bin/ instead of rebuilding.
EOF
            exit 0
            ;;
        *) log_error "Unknown argument: $arg" ;;
    esac
done

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------
log_info "Starting E2E Runtime Tests..."
"$SCRIPT_DIR/task.sh" stop > /dev/null 2>&1 || true

if [ "$SKIP_BUILD" = false ]; then
    "$SCRIPT_DIR/task.sh" build
else
    log_info "Skipping build (--skip-build). Verifying artifacts..."
    [ -x "$PICOBOXD_BIN" ] || log_error "Agent binary missing at $PICOBOXD_BIN"
    [ -x "$PICOBOX_MASTER_BIN" ] || log_error "Master binary missing at $PICOBOX_MASTER_BIN"
fi

"$SCRIPT_DIR/prepare-rootfs.sh" > /dev/null

export PICOBOX_API_TOKEN="${PICOBOX_API_TOKEN:-e2e-secret-token}"

"$PICOBOX_MASTER_BIN" > "$LOG_DIR/master_e2e.log" 2>&1 &
MASTER_PID=$!
save_pid master_e2e "$MASTER_PID"
wait_for_port 127.0.0.1 50051
wait_for_port 127.0.0.1 3000

"$PICOBOXD_BIN" > "$LOG_DIR/agent_e2e.log" 2>&1 &
AGENT_PID=$!
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

# -----------------------------------------------------------------------------
# Test cases
# -----------------------------------------------------------------------------

# Test 0: Agent registration via metrics stream.
wait_for_log "$LOG_DIR/master_e2e.log" "\[Master\] Received metrics from" 30 "agent registration" \
    || log_error "Agent did not register in time."

# Test 1: Auth rejection on invalid token.
log_info "Testing Authentication Failure..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:3000/api/deploy \
     -H "Authorization: Bearer wrong-token" \
     -H "Content-Type: application/json" \
     -d "{}")
if [ "$HTTP_STATUS" = "401" ]; then
    log_success "Auth Test Passed (Got 401 as expected)"
else
    log_error "Auth Test Failed! Expected 401, got $HTTP_STATUS"
fi

# Test 2: Deploy + log streaming.
ROOTFS_PATH="$PICOBOX_STORAGE_DIR/rootfs/busybox"
curl -s -X POST http://localhost:3000/api/deploy \
     -H "Authorization: Bearer $PICOBOX_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d "{\"hostname\": \"$(hostname)\", \"container_id\": \"test\", \"rootfs_image_url\": \"$ROOTFS_PATH\", \"command\": \"sh -c \\\"while true; do echo 'hello from container'; sleep 2; done\\\"\"}" \
     > /dev/null

wait_for_log "$LOG_DIR/agent_e2e.log"  "\[PicoBox-Agent\] Sandbox test active"        20 "sandbox active" \
    || log_error "Sandbox did not become active."
wait_for_log "$LOG_DIR/master_e2e.log" "\[Master\] \[Log\] test: hello from container" 20 "log streaming" \
    || log_error "Log streaming did not reach master."
log_success "E2E Test & Log Streaming Passed!"

# Test 3: Auto scheduler (no hostname supplied).
log_info "Testing Automatic Scheduler (no hostname)..."
curl -s -X POST http://localhost:3000/api/deploy \
     -H "Authorization: Bearer $PICOBOX_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d "{\"container_id\": \"sched-test\", \"rootfs_image_url\": \"$ROOTFS_PATH\", \"command\": \"echo 'sched-ok'\"}" \
     > /dev/null

wait_for_log "$LOG_DIR/master_e2e.log" "\[Scheduler\] Automatically selected node"       15 "scheduler decision" \
    || log_error "Scheduler did not auto-select."
wait_for_log "$LOG_DIR/agent_e2e.log"  "\[PicoBox-Agent\] Sandbox sched-test active"     15 "sched-test sandbox" \
    || log_error "Sandbox sched-test did not activate."
log_success "Automatic Scheduler Test Passed!"

# Test 4: WebSocket terminal roundtrip. Skips cleanly when python/websockets is unavailable.
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

log_success "All E2E tests passed."
