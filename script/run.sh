#!/usr/bin/env bash
# PicoBox Full-Stack Runner
# This script starts the Master control plane, a dummy Daemon agent, and the Web Dashboard.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/versions.sh"
load_nvm

echo "[Run] Starting PicoBox Full-Stack Environment..."

# Ensure binaries are built
if [ ! -f "bin/picobox-master" ] || [ ! -f "bin/picoboxd" ]; then
    echo "[Run] Binaries not found. Running build script first..."
    ./script/build.sh
fi

# Ensure logs directory exists
mkdir -p logs

echo "[Run] 1. Starting PicoBox Master Node (REST: 3000, gRPC: 50051)..."
./bin/picobox-master > logs/master.log 2>&1 &
MASTER_PID=$!

# Give the master server a moment to bind ports using wait loop
echo "[Run] Waiting for Master gRPC port (50051) to be ready..."
MAX_RETRIES=15; COUNT=0
while ! bash -c '< /dev/tcp/127.0.0.1/50051' 2>/dev/null && [ $COUNT -lt $MAX_RETRIES ]; do sleep 1; COUNT=$((COUNT+1)); done

if [ $COUNT -eq $MAX_RETRIES ]; then
    echo "[Run] ERROR: Master server failed to start on port 50051. Check logs/master.log"
    kill $MASTER_PID 2>/dev/null || true
    exit 1
fi

echo "[Run] 2. Starting PicoBox Dummy Daemon (pico-worker-1)..."
./bin/picoboxd > logs/daemon.log 2>&1 &
DAEMON_PID=$!

echo "[Run] 3. Starting Next.js Web Dashboard (Port: 3001)..."
if [ ! -d "web/node_modules" ]; then
    echo "[Run] Installing Web dependencies..."
    (cd web && npm install) > logs/web_install.log 2>&1
fi
(cd web && npm run dev) > logs/web.log 2>&1 &
WEB_PID=$!

echo "================================================================="
echo "✅ All services are running in the background!"
echo ""
echo "📡 Master REST API : http://localhost:3000/api/nodes"
echo "🌍 Web Dashboard   : http://localhost:3001"
echo ""
echo "🔎 Logs can be viewed with:"
echo "   - Master: tail -f logs/master.log"
echo "   - Daemon: tail -f logs/daemon.log"
echo "   - Web:    tail -f logs/web.log"
echo ""
echo "🛑 Press [CTRL+C] to stop all services and exit."
echo "================================================================="

# Trap INT and TERM signals to cleanly shut down background processes
trap "echo ''; echo '[Run] Stopping all services...'; kill $MASTER_PID $DAEMON_PID $WEB_PID 2>/dev/null || true; exit 0" SIGINT SIGTERM

# Wait indefinitely for background processes until interrupted
wait
