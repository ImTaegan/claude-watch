#!/usr/bin/env bash
# Install the Claude Watcher daemon as a launchd LaunchAgent so it starts at
# login and restarts if it crashes. Idempotent.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON="$DIR/.venv/bin/python"
SCRIPT="$DIR/claude_watch_daemon.py"
LOG="$HOME/.claude/claude-watch-daemon.log"
LABEL="com.claudewatch.daemon"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
TEMPLATE="$DIR/com.claudewatch.daemon.plist.template"

[ -x "$PYTHON" ] || { echo "venv python not found at $PYTHON — create it first (see README)"; exit 1; }

mkdir -p "$HOME/Library/LaunchAgents"
sed -e "s#__PYTHON__#$PYTHON#g" -e "s#__SCRIPT__#$SCRIPT#g" \
    -e "s#__WORKDIR__#$DIR#g" -e "s#__LOG__#$LOG#g" \
    "$TEMPLATE" > "$PLIST"

# Free the port: stop any manually-started daemon so launchd can bind it.
pkill -f "claude_watch_daemon.py" 2>/dev/null || true
sleep 1

UID_NUM="$(id -u)"
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST"
launchctl kickstart -k "gui/$UID_NUM/$LABEL" 2>/dev/null || true

echo "Installed launchd agent: $PLIST"
echo "The daemon now starts at login and restarts if it crashes. Logs: $LOG"
echo "To remove: launchctl bootout gui/$UID_NUM/$LABEL && rm $PLIST"
