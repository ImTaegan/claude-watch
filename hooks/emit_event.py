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


# The Notification hook fires both for genuine prompts (Claude is blocked
# waiting for you to answer a question or grant tool permission) AND for the
# idle reminder after you've been away. We only want "needs input" for the
# former. Suppressing biases safe: anything not clearly an idle nudge still
# pings, so a real question is never silently dropped.
NOTIFY_EVENTS = {"needs_input", "notify"}


def _is_idle_nudge(data):
    msg = (data.get("message") or "").lower()
    ntype = (data.get("notification_type") or "").lower()
    if "idle" in ntype:
        return True
    if "waiting for your input" in msg or "is waiting for" in msg:
        return True
    return False


def _log_notification(data, decision):
    # Temporary: capture real Notification payloads so the idle heuristic can
    # be tuned to the exact text Claude Code sends. Best-effort, harmless.
    try:
        with open("/tmp/claude_watch_notif.log", "a") as f:
            f.write(f"{decision}\t{json.dumps(data)}\n")
    except Exception:
        pass


def _clean_message(msg):
    """Trim a Notification message into a short 'waiting reason'."""
    if not msg:
        return None
    m = str(msg).strip()
    if m.lower().startswith("claude "):
        m = m[len("claude "):]
    return (m[:60] or None)


def _tool_detail(tool, ti):
    """A short, human label for what a tool is acting on."""
    if not isinstance(ti, dict):
        return None

    def base(p):
        return os.path.basename(str(p).rstrip("/")) or (str(p) or None)

    if tool == "Bash":
        cmd = (ti.get("command") or "").strip()
        return cmd[:48] or None
    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit", "Read", "NotebookRead"):
        return base(ti.get("file_path") or ti.get("notebook_path") or "")
    if tool in ("Grep", "Glob"):
        return ti.get("pattern")
    if tool == "LS":
        return base(ti.get("path") or "")
    if tool == "Task":
        return ti.get("description") or ti.get("subagent_type")
    if tool == "WebFetch":
        return ti.get("url")
    if tool == "WebSearch":
        return ti.get("query")
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

    detail = None
    if event in NOTIFY_EVENTS:
        idle = _is_idle_nudge(data)
        _log_notification(data, "suppressed-idle" if idle else "needs_input")
        if idle:
            return  # leave the agent's prior state (e.g. "done") untouched
        event = "needs_input"
        detail = _clean_message(data.get("message"))  # what it's waiting for

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
        d = _tool_detail(tool, data.get("tool_input"))
        if d:
            detail = d
    if detail:
        payload["detail"] = detail
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
