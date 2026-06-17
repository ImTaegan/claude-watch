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
