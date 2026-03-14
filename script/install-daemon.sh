#!/usr/bin/env bash
# script/install-daemon.sh
# PicoBox Daemon OS Native Installer

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run this installer as root (sudo)."
  exit 1
fi

DAEMON_BIN="bin/picoboxd"
SERVICE_TEMPLATE="pkg/daemon/picoboxd.service"
TARGET_BIN_DIR="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"

echo "[Install] Installing PicoBox Daemon..."

if [ ! -f "$DAEMON_BIN" ]; then
    echo "[Error] Daemon binary not found at $DAEMON_BIN. Please build it first."
    exit 1
fi

if [ ! -f "$SERVICE_TEMPLATE" ]; then
    echo "[Error] Service template not found at $SERVICE_TEMPLATE."
    exit 1
fi

echo "[Install] Copying binary to $TARGET_BIN_DIR..."
cp $DAEMON_BIN $TARGET_BIN_DIR/picoboxd
chmod +x $TARGET_BIN_DIR/picoboxd

echo "[Install] Setting up systemd service..."
cp $SERVICE_TEMPLATE $SYSTEMD_DIR/picoboxd.service
chmod 644 $SYSTEMD_DIR/picoboxd.service

echo "[Install] Reloading systemd manager configuration..."
systemctl daemon-reload

echo "[Install] Enabling and starting picoboxd.service..."
systemctl enable picoboxd.service
systemctl restart picoboxd.service

echo "[Install] Installation complete! Check status with: systemctl status picoboxd"
