#!/usr/bin/env bash
# PicoBox Daemon OS Native Installer

set -e

# 0. Load Environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if [ "$EUID" -ne 0 ]; then
  log_error "Please run this installer as root (sudo)."
fi

DAEMON_BIN="bin/picoboxd"
SERVICE_TEMPLATE="pkg/daemon/picoboxd.service"
TARGET_BIN_DIR="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"

log_info "Installing PicoBox Daemon..."

if [ ! -f "$DAEMON_BIN" ]; then
    log_error "Daemon binary not found at $DAEMON_BIN. Please build it first."
fi

if [ ! -f "$SERVICE_TEMPLATE" ]; then
    log_error "Service template not found at $SERVICE_TEMPLATE."
fi

log_info "Copying binary to $TARGET_BIN_DIR..."
cp $DAEMON_BIN $TARGET_BIN_DIR/picoboxd
chmod +x $TARGET_BIN_DIR/picoboxd

log_info "Setting up systemd service..."
cp $SERVICE_TEMPLATE $SYSTEMD_DIR/picoboxd.service
chmod 644 $SYSTEMD_DIR/picoboxd.service

log_info "Reloading systemd manager configuration..."
systemctl daemon-reload

log_info "Enabling and starting picoboxd.service..."
systemctl enable picoboxd.service
systemctl restart picoboxd.service

log_success "Installation complete! Check status with: systemctl status picoboxd"
