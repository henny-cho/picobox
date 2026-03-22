#!/usr/bin/env bash
# PicoBox RootFS Preparation Script

set -e

# 0. Load Environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Use PICOBOX_STORAGE_DIR if set, otherwise default to .storage
STORAGE_DIR="${PICOBOX_STORAGE_DIR:-$ROOT_DIR/.storage}"
ROOTFS_DIR="${1:-$STORAGE_DIR/rootfs/busybox}"

log_info "Preparing minimal filesystem in $ROOTFS_DIR..."

# 1. Create directory structure
rm -rf "$ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR"/{bin,dev,etc,proc,sys,tmp,var}

# 2. Copy busybox binary
BUSYBOX_BIN=$(which busybox)
cp "$BUSYBOX_BIN" "$ROOTFS_DIR/bin/busybox"

# 3. Create essential links
ln -sf busybox "$ROOTFS_DIR/bin/sh"
ln -sf busybox "$ROOTFS_DIR/bin/ls"
ln -sf busybox "$ROOTFS_DIR/bin/echo"
ln -sf busybox "$ROOTFS_DIR/bin/sleep"

# 4. Create a dummy test script
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

log_success "Minimal RootFS prepared at $ROOTFS_DIR."

# 5. Create tarball version for testing agent's new feature
TARBALL_PATH="$ROOTFS_DIR.tar.gz"
log_info "Creating tarball: $TARBALL_PATH..."
(cd "$ROOTFS_DIR" && tar -czf "$TARBALL_PATH" .)
log_success "Tarball prepared at $TARBALL_PATH."
