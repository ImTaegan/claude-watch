#!/usr/bin/env bash
set -euo pipefail
command -v python3 >/dev/null || { echo "python3 required"; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EMIT="${SCRIPT_DIR}/emit_event.py"
SETTINGS="${HOME}/.claude/settings.json"
SNIPPET="${SCRIPT_DIR}/settings.snippet.json"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "${SETTINGS}.bak.$(date +%s)"

python3 - "$SETTINGS" "$SNIPPET" "$EMIT" <<'PY'
import json, sys
settings_path, snippet_path, emit = sys.argv[1], sys.argv[2], sys.argv[3]
with open(settings_path) as f: settings = json.load(f)
with open(snippet_path) as f: snippet = json.load(f)

hooks = settings.setdefault("hooks", {})

def is_cw_entry(e):
    # Match both the new (emit_event.py) and legacy (inline URL) installs
    # so re-running is idempotent and upgrades cleanly.
    for h in e.get("hooks", []):
        c = h.get("command", "")
        if "emit_event.py" in c or "127.0.0.1:7459/event" in c:
            return True
    return False

for event, entries in snippet["hooks"].items():
    for e in entries:
        for h in e.get("hooks", []):
            if "command" in h:
                h["command"] = h["command"].replace("__EMIT_PATH__", emit)
    existing = hooks.get(event, [])
    hooks[event] = [e for e in existing if not is_cw_entry(e)]
    hooks[event].extend(entries)

with open(settings_path, "w") as f: json.dump(settings, f, indent=2)
print(f"Merged Claude Watcher hooks into {settings_path}")
print(f"Hook script: {emit}")
PY

echo "Done. Backup saved alongside settings.json."
echo "Restart Claude Code sessions for the new hooks to take effect."
