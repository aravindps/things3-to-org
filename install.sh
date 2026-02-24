#!/bin/bash
# install.sh -- sets up things3-org-backup launchd agent
# Usage: bash install.sh [hour] [minute]
#   hour   : 0-23  (default: 9)
#   minute : 0-59  (default: 0)
# Example: bash install.sh 21 30   -> runs at 21:30 every day

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/Scripts/things3-backup"
PLIST_NAME="com.things3backup.daily"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
BACKUP_HOUR="${1:-9}"
BACKUP_MINUTE="${2:-0}"

if ! [[ "$BACKUP_HOUR"   =~ ^([0-9]|1[0-9]|2[0-3])$ ]]; then
  echo "ERROR: Invalid hour '$BACKUP_HOUR' (must be 0-23)"; exit 1
fi
if ! [[ "$BACKUP_MINUTE" =~ ^([0-9]|[1-5][0-9])$ ]]; then
  echo "ERROR: Invalid minute '$BACKUP_MINUTE' (must be 0-59)"; exit 1
fi

echo "Installing Things3 Org Backup..."
echo "  Schedule : daily at $(printf '%02d:%02d' "$BACKUP_HOUR" "$BACKUP_MINUTE")"
echo "  Install  : $INSTALL_DIR"

mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/things3-backup.applescript" "$INSTALL_DIR/things3-backup.applescript"
echo "OK  Script copied"

mkdir -p "$LAUNCH_AGENTS"
sed \
    -e "s|__SCRIPT_PATH__|$INSTALL_DIR/things3-backup.applescript|g" \
    -e "s|__HOUR__|$BACKUP_HOUR|g" \
    -e "s|__MINUTE__|$BACKUP_MINUTE|g" \
    -e "s|__LOG_PATH__|$INSTALL_DIR|g" \
    "$SCRIPT_DIR/com.things3backup.daily.plist.template" \
    > "$LAUNCH_AGENTS/$PLIST_NAME.plist"
echo "OK  Plist written"

launchctl unload "$LAUNCH_AGENTS/$PLIST_NAME.plist" 2>/dev/null || true
launchctl load   "$LAUNCH_AGENTS/$PLIST_NAME.plist"
echo "OK  Agent loaded"

echo ""
echo "========================================"
echo "  Setup complete!"
echo "  Script  : $INSTALL_DIR/things3-backup.applescript"
echo "  Plist   : $LAUNCH_AGENTS/$PLIST_NAME.plist"
echo "  Log     : $INSTALL_DIR/things3-backup.log"
echo "  Backups : $HOME/Documents/Things3-Backups/"
echo "  Time    : daily at $(printf '%02d:%02d' "$BACKUP_HOUR" "$BACKUP_MINUTE")"
echo "========================================"
echo ""
echo "Run now  : osascript \"$INSTALL_DIR/things3-backup.applescript\""
echo "View log : tail -f \"$INSTALL_DIR/things3-backup.log\""
echo "Remove   : bash \"$SCRIPT_DIR/uninstall.sh\""
