#!/usr/bin/env bash
# PicoBox Local CI/CD Simulation Script (act)
# This script runs the GitHub Actions workflow locally using 'act'.
# It is specifically optimized for PicoBox requirements (Privileged mode for Namespaces/Cgroups).

set -e

# Ensure we are in the project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

echo "[Act-Test] Starting Local CI/CD Simulation..."

# 1. Check if 'act' is installed
if ! command -v act &> /dev/null; then
    echo "[Act-Test] ERROR: 'act' is not installed."
    echo "[Act-Test] Please install it from: https://github.com/nektos/act"
    echo "[Act-Test] Example (via curl): curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash"
    exit 1
fi

# 2. Detect Architecture for optimal image selection
ARCH_FLAG=""
if [[ $(uname -m) == "aarch64" ]]; then
    echo "[Act-Test] ARM64 architecture detected. Applying container-architecture flag..."
    ARCH_FLAG="--container-architecture linux/arm64"
fi

# 3. Define common flags
# --container-options "--privileged": Essential for PicoBox to perform namespace/cgroup operations inside container
# --container-daemon-socket: Connect to host docker daemon
FLAGS="--container-options \"--privileged\" --container-daemon-socket /var/run/docker.sock $ARCH_FLAG"

# 4. Check for Docker daemon access
ACT_CMD="act"
if [ ! -w /var/run/docker.sock ]; then
    echo "[Act-Test] WARNING: Current user does not have access to /var/run/docker.sock."
    if command -v sudo &> /dev/null; then
        echo "[Act-Test] 'sudo' detected. Attempting to run 'act' with sudo..."
        ACT_CMD="sudo act"
    else
        echo "[Act-Test] ERROR: 'sudo' not found and no access to docker socket."
        echo "[Act-Test] Please add your user to the 'docker' group: sudo usermod -aG docker \$USER"
        exit 1
    fi
fi

# 5. Execute act
echo "[Act-Test] Running 'act' with privileged mode..."
echo "[Act-Test] Command: $ACT_CMD -j build $FLAGS"

# Note: We focus on the 'build' job which contains the full validation loop.
$ACT_CMD -j build $FLAGS

echo "[Act-Test] Local CI/CD simulation completed."
