"""Sum today's output tokens across all Claude Code session transcripts.

Transcripts live at ~/.claude/projects/<encoded-cwd>/<session>.jsonl; each
assistant line carries message.usage.output_tokens. We only open files touched
today and only count entries whose timestamp is today's date — a rough but cheap
"work done today" gauge. Runs off the HTTP path on a background thread.
"""
import datetime
import glob
import json
import os


def _today(now):
    midnight = datetime.datetime.fromtimestamp(now).replace(
        hour=0, minute=0, second=0, microsecond=0)
    return midnight.timestamp(), midnight.date().isoformat()


def scan_today_output_tokens(projects_dir, now):
    midnight_ts, today_iso = _today(now)
    total = 0
    for path in glob.glob(os.path.join(projects_dir, "*", "*.jsonl")):
        try:
            if os.path.getmtime(path) < midnight_ts:
                continue
            with open(path, encoding="utf-8") as f:
                for line in f:
                    if '"usage"' not in line:
                        continue
                    try:
                        entry = json.loads(line)
                    except Exception:
                        continue
                    if entry.get("type") != "assistant":
                        continue
                    if not str(entry.get("timestamp", "")).startswith(today_iso):
                        continue
                    usage = (entry.get("message") or {}).get("usage") or {}
                    total += usage.get("output_tokens", 0) or 0
        except Exception:
            continue
    return total
