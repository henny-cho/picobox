#!/usr/bin/env bash
# script/prepare-rootfs.sh
# Creates a minimal RootFS for PicoBox E2E testing using busybox.

set -e

# Color Definitions
GREEN='\033[0;32m'
BOLD_CYAN='\033[1;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ROOTFS_DIR="$ROOT_DIR/test_rootfs"

echo -e "${BOLD_CYAN}[RootFS] Preparing minimal filesystem in $ROOTFS_DIR...${NC}"

# 1. Create directory structure
rm -rf "$ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR"/{bin,dev,etc,proc,sys,tmp,var}

# 2. Copy busybox binary
BUSYBOX_BIN=$(which busybox)
cp "$BUSYBOX_BIN" "$ROOTFS_DIR/bin/busybox"

# 3. Create essential links
# Note: We only need enough to run a shell or a simple script.
ln -s busybox "$ROOTFS_DIR/bin/sh"
ln -s busybox "$ROOTFS_DIR/bin/ls"
ln -s busybox "$ROOTFS_DIR/bin/echo"
ln -s busybox "$ROOTFS_DIR/bin/sleep"

# 4. Create a dummy test script inside the rootfs
cat <<EOF > "$ROOTFS_DIR/test-init.sh"
#!/bin/sh
echo "--- PicoBox Container Started ---"
echo "Hostname: \$(hostname)"
echo "PID: \$\$"
echo "Environment:"
env
echo "Sleeping for 60 seconds..."
sleep 60
EOF
chmod +x "$ROOTFS_DIR/test-init.sh"

echo -e "${GREEN}[RootFS] Minimal RootFS prepared at $ROOTFS_DIR.${NC}"
