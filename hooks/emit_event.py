#!/usr/bin/env python3
"""Claude Watcher hook: read hook stdin JSON + env, POST a compact event.

Usage: emit_event.py <event>   where event is running|done|needs_input|ended

Best-effort: never blocks Claude Code and swallows every error. A hard alarm
backstop guarantees the process can't hang the agent.
"""
import json
import os
import signal
import subprocess
import sys
import urllib.request

URL = "http://127.0.0.1:7459/event"

try:
    signal.alarm(3)  # hard backstop; never let a hook hang the agent
except Exception:
    pass


def _tty():
    """The terminal device backing this agent, e.g. '/dev/ttys003'.

    A hook subprocess has no controlling tty of its own, but an ancestor
    (the Claude Code / shell process) does. Walk up the parent chain until a
    real tty appears. Returns None if none is found (used to focus the tab)."""
    pid = os.getpid()
    for _ in range(8):
        try:
            line = subprocess.run(
                ["ps", "-o", "tty=,ppid=", "-p", str(pid)],
                capture_output=True, text=True, timeout=1,
            ).stdout.strip()
        except Exception:
            return None
        if not line:
            return None
        parts = line.split()
        tty, ppid = parts[0], parts[-1]
        if tty and tty != "??":
            return tty if tty.startswith("/dev/") else f"/dev/{tty}"
        if not ppid.isdigit() or ppid in ("0", "1") or ppid == str(pid):
            return None
        pid = int(ppid)
    return None


def _repo_root(cwd):
    """The git repo root for cwd, so the project label is the repo name
    (stable across subdirectories) rather than whatever folder a tool ran in."""
    if not cwd:
        return None
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=1,
        ).stdout.strip()
        return out or None
    except Exception:
        return None


def main():
    event = sys.argv[1] if len(sys.argv) > 1 else "running"
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}

    cwd = data.get("cwd", "")
    root = _repo_root(cwd) or cwd
    payload = {
        "session_id": data.get("session_id", "?"),
        "cwd": root,
        "event": event,
    }
    if root:
        payload["project"] = os.path.basename(root.rstrip("/")) or root
    tool = data.get("tool_name")
    if tool:
        payload["tool"] = tool
    term = os.environ.get("TERM_PROGRAM")
    if term:
        payload["term"] = term
    tty = _tty()
    if tty:
        payload["tty"] = tty

    try:
        req = urllib.request.Request(
            URL, data=json.dumps(payload).encode(), method="POST"
        )
        urllib.request.urlopen(req, timeout=1)
    except Exception:
        pass


if __name__ == "__main__":
    main()
