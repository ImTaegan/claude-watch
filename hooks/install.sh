#!/usr/bin/env bash
set -euo pipefail
SETTINGS="${HOME}/.claude/settings.json"
SNIPPET="$(dirname "$0")/settings.snippet.json"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "${SETTINGS}.bak.$(date +%s)"

python3 - "$SETTINGS" "$SNIPPET" <<'PY'
import json, sys
settings_path, snippet_path = sys.argv[1], sys.argv[2]
with open(settings_path) as f: settings = json.load(f)
with open(snippet_path) as f: snippet = json.load(f)
hooks = settings.setdefault("hooks", {})
for event, entries in snippet["hooks"].items():
    hooks.setdefault(event, [])
    hooks[event].extend(entries)
with open(settings_path, "w") as f: json.dump(settings, f, indent=2)
print(f"Merged Claude Watcher hooks into {settings_path}")
PY

echo "Done. Backup saved alongside settings.json."
echo "Start the daemon: cd daemon && source .venv/bin/activate && python claude_watch_daemon.py"
