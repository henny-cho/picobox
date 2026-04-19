#!/usr/bin/env bash
# Prepare a minimal busybox rootfs used by sandbox tests.
#
# Usage: prepare-rootfs.sh [<target-dir>] [--tarball]
#
#   target-dir  Defaults to $PICOBOX_STORAGE_DIR/rootfs/busybox.
#   --tarball   Also emit <target-dir>.tar.gz (for tests that consume an archive).

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

MAKE_TARBALL=false
TARGET_DIR=""
for arg in "$@"; do
    case "$arg" in
        --tarball) MAKE_TARBALL=true ;;
        -h|--help)
            sed -n '2,8p' "$0"; exit 0 ;;
        *) TARGET_DIR="$arg" ;;
    esac
done

ROOTFS_DIR="${TARGET_DIR:-$PICOBOX_STORAGE_DIR/rootfs/busybox}"

log_info "Preparing minimal filesystem in $ROOTFS_DIR..."

rm -rf "$ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR"/{bin,dev,etc,proc,sys,tmp,var}

BUSYBOX_BIN=$(command -v busybox) \
    || log_error "busybox not found. Install it first (apt install busybox, etc)."
cp "$BUSYBOX_BIN" "$ROOTFS_DIR/bin/busybox"

for link in sh ls echo sleep; do
    ln -sf busybox "$ROOTFS_DIR/bin/$link"
done

cat > "$ROOTFS_DIR/test-init.sh" <<'EOF'
#!/bin/sh
echo "--- PicoBox Container Started ---"
echo "Hostname: $(hostname)"
echo "PID: $$"
echo "Environment:"
env
echo "Sleeping for 60 seconds..."
sleep 60
EOF
chmod +x "$ROOTFS_DIR/test-init.sh"

log_success "Minimal RootFS prepared at $ROOTFS_DIR."

if [ "$MAKE_TARBALL" = true ]; then
    TARBALL_PATH="$ROOTFS_DIR.tar.gz"
    log_info "Creating tarball: $TARBALL_PATH..."
    (cd "$ROOTFS_DIR" && tar -czf "$TARBALL_PATH" .)
    log_success "Tarball prepared at $TARBALL_PATH."
fi
