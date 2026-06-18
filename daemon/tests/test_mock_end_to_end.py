import json
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

DAEMON = Path(__file__).resolve().parents[1] / "claude_watch_daemon.py"

def _free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port

def _post(port, body):
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/event",
        data=json.dumps(body).encode(),
        method="POST",
    )
    urllib.request.urlopen(req, timeout=2).read()

def _get(port, path):
    raw = urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=2).read()
    return json.loads(raw)


def test_status_endpoint_reports_agents():
    port = _free_port()
    proc = subprocess.Popen(
        [sys.executable, str(DAEMON), "--mock", "--port", str(port),
         "--debounce", "0.05"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    try:
        time.sleep(1.0)
        _post(port, {"session_id": "s1", "event": "running", "cwd": "/x/projA"})
        _post(port, {"session_id": "s2", "event": "needs_input", "cwd": "/x/projB"})
        time.sleep(0.3)
        status = _get(port, "/status")
    finally:
        proc.terminate()
        proc.communicate(timeout=5)
    assert status["counts"]["running"] == 1
    assert status["counts"]["needs_input"] == 1
    assert status["agents"][0]["project"] == "projB"
    assert status["agents"][0]["state"] == 3
    assert all("age_seconds" in a for a in status["agents"])


def _post_to(port, path, body):
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}{path}",
        data=json.dumps(body).encode(), method="POST",
    )
    urllib.request.urlopen(req, timeout=2).read()


def test_usage_endpoint_updates_status():
    port = _free_port()
    proc = subprocess.Popen(
        [sys.executable, str(DAEMON), "--mock", "--port", str(port),
         "--debounce", "0.05"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    try:
        time.sleep(1.0)
        _post(port, {"session_id": "u1", "event": "running", "cwd": "/x/proj"})
        _post_to(port, "/usage", {
            "session_id": "u1", "context_pct": 42,
            "five_hour_pct": 50, "five_hour_resets_at": 111,
            "seven_day_pct": 7, "seven_day_resets_at": 222,
        })
        time.sleep(0.3)
        status = _get(port, "/status")
    finally:
        proc.terminate()
        proc.communicate(timeout=5)
    assert status["limits"]["five_hour"]["used_percentage"] == 50
    a = [x for x in status["agents"] if x["id"] == "u1"][0]
    assert a["context_pct"] == 42


def test_mock_emits_payload_lines():
    port = _free_port()
    proc = subprocess.Popen(
        [sys.executable, str(DAEMON), "--mock", "--port", str(port),
         "--debounce", "0.05"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    try:
        time.sleep(1.0)  # let server bind
        _post(port, {"session_id": "s1", "event": "running", "cwd": "/x/projA"})
        _post(port, {"session_id": "s2", "event": "needs_input", "cwd": "/x/projB"})
        time.sleep(0.5)
    finally:
        proc.terminate()
        out, _ = proc.communicate(timeout=5)
    payloads = [json.loads(l) for l in out.splitlines() if l.startswith("{")]
    assert payloads, f"no payloads in output:\n{out}"
    last = payloads[-1]
    assert last["r"] == 1 and last["u"] == 1
    assert last["top"] == "projB"
