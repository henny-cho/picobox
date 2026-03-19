#!/usr/bin/env bash
# PicoBox Test Automation Script
# This script executes all unit and integration tests across the monorepo.
# It is designed to be run both locally by developers and automatically within the CI/CD pipeline.
# It ensures all code meets the pre-defined Validation Loops before moving to the next Phase.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/versions.sh"
load_nvm

# Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD_RED='\033[1;31m'
BOLD_GREEN='\033[1;32m'
BOLD_YELLOW='\033[1;33m'
BOLD_CYAN='\033[1;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}[Build & Test] Starting Unified Validation Loop for PicoBox...${NC}"

# Ensure we are in the project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

# 1. Run Build Check (Mandatory first step)
run_build() {
    echo -e "${CYAN}[Build & Test] Step 1: Running Build Check (build.sh)...${NC}"
    if [ -f "$SCRIPT_DIR/build.sh" ]; then
        bash "$SCRIPT_DIR/build.sh" > /tmp/picobox_build.log 2>&1
        return $?
    fi
    return 0
}

# 2. Run Go Backend Tests (Daemon & Master)
run_go_tests() {
    echo -e "${CYAN}[Build & Test] Step 2: Running Go Tests (pkg/, cmd/)...${NC}"
    if [ -f "go.mod" ]; then
        CGO_ENABLED=1 go test -v -race ./... > /tmp/picobox_go_test.log 2>&1
        return $?
    fi
    return 0
}

# 3. Run TypeScript/Node.js Frontend Tests (Web Dashboard)
run_web_tests() {
    echo -e "${CYAN}[Build & Test] Step 3: Running Web Dashboard UI Tests...${NC}"
    if [ -d "web" ] && [ -f "web/package.json" ]; then
        (cd web && npm ci && npm run test) > /tmp/picobox_web_test.log 2>&1
        return $?
    fi
    return 0
}

# 4. Run GitHub Actions (act-test.sh)
run_act_tests() {
    if [[ "$ACT" == "true" || "$GITHUB_ACTIONS" == "true" ]]; then
        echo -e "${YELLOW}[Build & Test] Step 4: Skipping GitHub Actions (act-test.sh) in CI environment.${NC}"
        return 0
    fi
    echo -e "${CYAN}[Build & Test] Step 4: Running GitHub Actions (act-test.sh)...${NC}"
    if [ -f "$SCRIPT_DIR/act-test.sh" ]; then
        bash "$SCRIPT_DIR/act-test.sh" > /tmp/picobox_act_test.log 2>&1
        return $?
    fi
    return 0
}

# Execution Flow
EXIT_CODE=0

# Step 1 must pass before others run
run_build || EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    echo "-----------------------------------------------------------------"
    echo -e "${RED}[Build & Test] Step 1 FAILED. Aborting tests.${NC}"
    if [ -f /tmp/picobox_build.log ]; then tail -n 10 /tmp/picobox_build.log; fi
    exit $EXIT_CODE
fi

# Run remaining tests in parallel
run_go_tests &
GO_TEST_PID=$!

run_web_tests &
WEB_TEST_PID=$!

run_act_tests &
ACT_TEST_PID=$!

# Wait and capture results
GO_STATUS="${BOLD_GREEN}PASS${NC}"
wait $GO_TEST_PID || { EXIT_CODE=$?; GO_STATUS="${BOLD_RED}FAIL${NC}"; }

WEB_STATUS="${BOLD_GREEN}PASS${NC}"
wait $WEB_TEST_PID || { EXIT_CODE=$?; WEB_STATUS="${BOLD_RED}FAIL${NC}"; }

ACT_STATUS="${BOLD_GREEN}PASS${NC}"
wait $ACT_TEST_PID || { EXIT_CODE=$?; ACT_STATUS="${BOLD_RED}FAIL${NC}"; }

# Report results from logs for clarity
echo "-----------------------------------------------------------------"
echo -e "[Build & Test] Build Summary: ${BOLD_GREEN}PASS${NC}"
if [ -f /tmp/picobox_build.log ]; then tail -n 3 /tmp/picobox_build.log; fi
echo -e "[Build & Test] Go Test Summary: $GO_STATUS"
if [ -f /tmp/picobox_go_test.log ]; then tail -n 5 /tmp/picobox_go_test.log; fi
echo -e "[Build & Test] Web Test Summary: $WEB_STATUS"
if [ -f /tmp/picobox_web_test.log ]; then tail -n 5 /tmp/picobox_web_test.log; fi
echo -e "[Build & Test] Act Test Summary: $ACT_STATUS"
if [ -f /tmp/picobox_act_test.log ]; then tail -n 5 /tmp/picobox_act_test.log; fi
echo "-----------------------------------------------------------------"

if [ $EXIT_CODE -ne 0 ]; then
    echo -e "${RED}[Build & Test] ERROR: One or more test suites failed (Exit: $EXIT_CODE).${NC}"
    exit $EXIT_CODE
fi
echo -e "${GREEN}[Build & Test] Core validation suites passed.${NC}"

# 5. Full-Stack Integration Test (Optional)
if [[ "$*" == *"--fullstack"* ]]; then
    echo -e "${CYAN}[Build & Test] Step 5: Running Full-Stack Integration Test...${NC}"
    
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

echo -e "${GREEN}[Build & Test] All Validation Loops passed successfully!${NC}"
