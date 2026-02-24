#!/bin/bash
# uninstall.sh -- removes launchd agent and installed script
# Usage: bash uninstall.sh [--purge-backups]

set -e

INSTALL_DIR="$HOME/Scripts/things3-backup"
PLIST_NAME="com.things3backup.daily"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS/$PLIST_NAME.plist"
BACKUP_DIR="$HOME/Documents/Things3-Backups"

echo "Uninstalling Things3 Org Backup..."

if [ -f "$PLIST_PATH" ]; then
  launchctl unload "$PLIST_PATH" 2>/dev/null || true
  rm -f "$PLIST_PATH"
  echo "OK  Agent removed"
else
  echo "WARN  No agent plist at $PLIST_PATH"
fi

if [ -d "$INSTALL_DIR" ]; then
  rm -rf "$INSTALL_DIR"
  echo "OK  Script removed"
else
  echo "WARN  Install dir not found: $INSTALL_DIR"
fi

if [[ "${1:-}" == "--purge-backups" ]]; then
  if [ -d "$BACKUP_DIR" ]; then
    rm -rf "$BACKUP_DIR"
    echo "OK  Backups purged: $BACKUP_DIR"
  fi
else
  echo "INFO  Backups kept at: $BACKUP_DIR"
  echo "      Use --purge-backups to delete them too"
fi

echo ""
echo "========================================"
echo "  Uninstall complete"
echo "========================================"
