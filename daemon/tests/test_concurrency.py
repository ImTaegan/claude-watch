"""Regression test: concurrent POSTs must not cause dict-iteration races (Fix 1).

Spawns the daemon in --mock mode, then fires 8 threads × 25 events = 200 POSTs,
each with a distinct session_id. Every POST must return HTTP 204 — if the lock is
missing, the handler silently converts RuntimeError into a 400.
"""
import json
import socket
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path

DAEMON = Path(__file__).resolve().parents[1] / "claude_watch_daemon.py"

THREADS = 8
EVENTS_PER_THREAD = 25  # 200 total POSTs


def _free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def _post_one(port, session_id, thread_idx, event_idx, results, lock):
    """POST a single event and record the HTTP status code."""
    body = json.dumps({
        "session_id": session_id,
        "event": "running",
        "cwd": f"/projects/proj{thread_idx}",
    }).encode()
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/event",
        data=body,
        method="POST",
    )
    try:
        resp = urllib.request.urlopen(req, timeout=5)
        status = resp.status
    except urllib.error.HTTPError as e:
        status = e.code
    except Exception:
        status = -1
    with lock:
        results.append(status)


def test_concurrent_posts_all_return_204():
    port = _free_port()
    proc = subprocess.Popen(
        [sys.executable, str(DAEMON), "--mock", "--port", str(port),
         "--debounce", "0.05"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        time.sleep(1.2)  # let server bind

        results = []
        results_lock = threading.Lock()
        threads = []

        for t_idx in range(THREADS):
            def run_thread(thread_idx=t_idx):
                for e_idx in range(EVENTS_PER_THREAD):
                    # Each POST uses a unique session_id to maximise dict mutation churn
                    sid = f"t{thread_idx}-e{e_idx}"
                    _post_one(port, sid, thread_idx, e_idx, results, results_lock)

            thr = threading.Thread(target=run_thread)
            threads.append(thr)

        # Start all threads at once for maximum concurrency
        for thr in threads:
            thr.start()
        for thr in threads:
            thr.join(timeout=30)

        # Allow a short drain so the mock writer can flush
        time.sleep(0.5)

    finally:
        proc.terminate()
        out, _ = proc.communicate(timeout=5)

    total = THREADS * EVENTS_PER_THREAD
    assert len(results) == total, (
        f"Expected {total} results, got {len(results)}"
    )

    non_204 = [r for r in results if r != 204]
    assert not non_204, (
        f"{len(non_204)} POSTs did NOT return 204: {set(non_204)!r}\n"
        "This indicates a data race in the HTTP handler — the lock is missing or broken."
    )
