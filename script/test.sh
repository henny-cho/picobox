#!/usr/bin/env bash
# PicoBox Test Automation Script
# This script executes all unit and integration tests across the monorepo.
# It is designed to be run both locally by developers and automatically within the CI/CD pipeline.
# It ensures all code meets the pre-defined Validation Loops before moving to the next Phase.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/versions.sh"
load_nvm

echo "[Test] Starting Validation Loop for PicoBox..."

# Ensure we are in the project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

# 1. Run Go Backend Tests (Daemon & Master)
run_go_tests() {
    echo "[Test] Step 1: Running Go Tests (pkg/, cmd/)..."
    if [ -f "go.mod" ]; then
        CGO_ENABLED=1 go test -v -race ./... > /tmp/picobox_go_test.log 2>&1
        return $?
    fi
    return 0
}

# 2. Run TypeScript/Node.js Frontend Tests (Web Dashboard)
run_web_tests() {
    echo "[Test] Step 2: Running Web Dashboard UI Tests..."
    if [ -d "web" ] && [ -f "web/package.json" ]; then
        (cd web && npm ci && npm run test) > /tmp/picobox_web_test.log 2>&1
        return $?
    fi
    return 0
}

# 3. Run GitHub Actions (act-test.sh)
run_act_tests() {
    if [[ "$ACT" == "true" || "$GITHUB_ACTIONS" == "true" ]]; then
        echo "[Test] Step 3: Skipping GitHub Actions (act-test.sh) in CI environment."
        return 0
    fi
    echo "[Test] Step 3: Running GitHub Actions (act-test.sh)..."
    if [ -f "$SCRIPT_DIR/act-test.sh" ]; then
        bash "$SCRIPT_DIR/act-test.sh" > /tmp/picobox_act_test.log 2>&1
        return $?
    fi
    return 0
}

# Run in parallel
run_go_tests &
GO_TEST_PID=$!

run_web_tests &
WEB_TEST_PID=$!

run_act_tests &
ACT_TEST_PID=$!

# Wait and capture results
EXIT_CODE=0
wait $GO_TEST_PID || EXIT_CODE=$?
wait $WEB_TEST_PID || EXIT_CODE=$?
wait $ACT_TEST_PID || EXIT_CODE=$?

# Report results from logs for clarity
echo "-----------------------------------------------------------------"
echo "[Test] Go Test Summary:"
if [ -f /tmp/picobox_go_test.log ]; then tail -n 5 /tmp/picobox_go_test.log; fi
echo "[Test] Web Test Summary:"
if [ -f /tmp/picobox_web_test.log ]; then tail -n 5 /tmp/picobox_web_test.log; fi
echo "[Test] Act Test Summary:"
if [ -f /tmp/picobox_act_test.log ]; then tail -n 5 /tmp/picobox_act_test.log; fi
echo "-----------------------------------------------------------------"

if [ $EXIT_CODE -ne 0 ]; then
    echo "[Test] ERROR: One or more test suites failed (Exit: $EXIT_CODE)."
    exit $EXIT_CODE
fi
echo "[Test] Core validation suites passed."

# 4. Full-Stack Integration Test (Optional)
if [[ "$*" == *"--fullstack"* ]]; then
    echo "[Test] Step 4: Running Full-Stack Integration Test..."
    
    # Ensure binaries are built
    if [ ! -f "./bin/picobox-master" ] || [ ! -f "./bin/picoboxd" ]; then
        echo "[Test] Binaries not found in ./bin. Running build.sh first..."
        ./script/build.sh
    fi

    # Create logs directory if it doesn't exist
    mkdir -p logs

    echo "[Test] Starting Master Server..."
    ./bin/picobox-master > logs/master_test.log 2>&1 &
    MASTER_PID=$!
    
    # Wait for Master port to be ready
    echo "[Test] Waiting for Master port (50051) to be ready..."
    MAX_RETRIES=10; COUNT=0
    while ! bash -c '< /dev/tcp/127.0.0.1/50051' 2>/dev/null && [ $COUNT -lt $MAX_RETRIES ]; do sleep 1; COUNT=$((COUNT+1)); done

    echo "[Test] Starting Daemon..."
    ./bin/picoboxd > logs/daemon_test.log 2>&1 &
    DAEMON_PID=$!
    
    sleep 5
    
    if ps -p $MASTER_PID > /dev/null && ps -p $DAEMON_PID > /dev/null; then
        echo "[Test] Full-Stack processes are running. Integration check passed."
    else
        echo "[Test] ERROR: One or more processes failed to start."
        exit 1
    fi
    
    kill $MASTER_PID $DAEMON_PID
    echo "[Test] Full-Stack integration test passed."
fi

echo "[Test] All Validation Loops passed successfully!"
