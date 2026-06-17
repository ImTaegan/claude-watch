# Claude Watcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a wearable M5StickC Plus2 that shows, over Bluetooth LE, the live state (running / done / needs-input) of every Claude Code agent running across all terminals on the laptop.

**Architecture:** Claude Code hooks fire-and-forget HTTP events to a long-running Python daemon on localhost. The daemon aggregates per-session state and is the only process that holds the BLE connection, pushing a compact status payload to the watch whenever the aggregate changes. The watch firmware (ESP32) renders a color-coded summary with a button-cycled detail view.

**Tech Stack:** Python 3.14 + `bleak` (BLE central) + stdlib `http.server`/`asyncio` (daemon); PlatformIO + Arduino + `M5Unified` + `NimBLE-Arduino` + `ArduinoJson` (firmware); `curl` hooks in `~/.claude/settings.json`.

## Global Constraints

- Hooks MUST never block Claude: every hook uses `curl -s -m 1 ... || true` (1-second hard timeout, failure swallowed).
- Daemon HTTP server binds `127.0.0.1` only (never `0.0.0.0`).
- Daemon dependencies limited to `bleak` (everything else stdlib). Aggregator logic (`aggregator.py`) MUST be pure Python with no async/IO/BLE imports so it is unit-testable without hardware.
- State urgency order is fixed: `needs_input (3) > done (2) > running (1) > idle (0)`.
- BLE identifiers (shared by firmware and daemon): device name `ClaudeWatch`; Service UUID `c1a0de00-0001-4a00-b000-000000000001`; Status characteristic UUID `c1a0de00-0002-4a00-b000-000000000002`.
- Wire payload is compact JSON: `{"u":int,"r":int,"d":int,"i":int,"top":str,"sessions":[{"project":str,"state":int},...≤5]}`.
- Event server port default `7459`. Idle-session GC default `900` seconds. BLE push debounce default `0.25` seconds.
- macOS note: bleak addresses on macOS are CoreBluetooth UUIDs, not hardware MACs. The config field is named `address` and stores whatever `BleakScanner` reports.
- Device serial port for flashing: `/dev/cu.usbserial-5A6C0505221`.
- Use a Python venv at `daemon/.venv` (Python 3.14). All `python`/`pytest` commands below assume it is activated.

---

## Phase 1 — Daemon core (mock, no hardware)

### Task 1: Scaffold + session state model

**Files:**
- Create: `daemon/requirements.txt`
- Create: `daemon/aggregator.py`
- Create: `daemon/tests/test_aggregator.py`
- Create: `daemon/tests/__init__.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - Constants `IDLE=0, RUNNING=1, DONE=2, NEEDS_INPUT=3`.
  - `EVENT_TO_STATE: dict[str,int]` mapping `"idle"|"running"|"done"|"needs_input"` to the state ints.
  - `class SessionRegistry` with `update(session_id: str, project: str, event: str, now: float) -> None`. Event `"ended"` removes the session; other events set `{project, state, last_seen}`.

- [ ] **Step 1: Create venv and requirements**

```bash
cd /Users/taeganmurphy/Websites/claude-watchh
python3 -m venv daemon/.venv
source daemon/.venv/bin/activate
printf 'bleak>=0.22\n' > daemon/requirements.txt
pip install -r daemon/requirements.txt pytest
```
Expected: bleak + pytest install cleanly.

- [ ] **Step 2: Write the failing test**

Create `daemon/tests/__init__.py` (empty) and `daemon/tests/test_aggregator.py`:

```python
from aggregator import SessionRegistry, RUNNING, NEEDS_INPUT, DONE

def test_update_sets_state_and_removes_on_ended():
    r = SessionRegistry()
    r.update("s1", "projA", "running", now=100.0)
    assert r._sessions["s1"]["state"] == RUNNING
    assert r._sessions["s1"]["project"] == "projA"
    assert r._sessions["s1"]["last_seen"] == 100.0

    r.update("s1", "projA", "needs_input", now=101.0)
    assert r._sessions["s1"]["state"] == NEEDS_INPUT
    assert r._sessions["s1"]["last_seen"] == 101.0

    r.update("s1", "projA", "ended", now=102.0)
    assert "s1" not in r._sessions
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd daemon && python -m pytest tests/test_aggregator.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'aggregator'`.

- [ ] **Step 4: Write minimal implementation**

Create `daemon/aggregator.py`:

```python
"""Pure session-state aggregation. No async, no IO, no BLE — unit-testable."""

IDLE = 0
RUNNING = 1
DONE = 2
NEEDS_INPUT = 3

EVENT_TO_STATE = {
    "idle": IDLE,
    "running": RUNNING,
    "done": DONE,
    "needs_input": NEEDS_INPUT,
}


class SessionRegistry:
    def __init__(self):
        # session_id -> {"project": str, "state": int, "last_seen": float}
        self._sessions = {}

    def update(self, session_id, project, event, now):
        if event == "ended":
            self._sessions.pop(session_id, None)
            return
        if event not in EVENT_TO_STATE:
            raise ValueError(f"unknown event: {event}")
        self._sessions[session_id] = {
            "project": project,
            "state": EVENT_TO_STATE[event],
            "last_seen": now,
        }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd daemon && python -m pytest tests/test_aggregator.py -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add daemon/requirements.txt daemon/aggregator.py daemon/tests/
git commit -m "feat(daemon): session registry update + state model"
```

---

### Task 2: Aggregate counts, top, and session list

**Files:**
- Modify: `daemon/aggregator.py`
- Modify: `daemon/tests/test_aggregator.py`

**Interfaces:**
- Consumes: `SessionRegistry` from Task 1.
- Produces: `SessionRegistry.aggregate(max_sessions: int = 5) -> dict` returning
  `{"u":int,"r":int,"d":int,"i":int,"top":str,"sessions":[{"project":str,"state":int},...]}`.
  `sessions` is sorted by urgency desc then `last_seen` desc, truncated to `max_sessions`.
  `top` is the project of the first (most-urgent) session, or `""` if none.

- [ ] **Step 1: Write the failing test**

Append to `daemon/tests/test_aggregator.py`:

```python
def test_aggregate_counts_top_and_order():
    r = SessionRegistry()
    r.update("a", "projA", "running", now=1.0)
    r.update("b", "projB", "running", now=2.0)
    r.update("c", "projC", "needs_input", now=3.0)
    r.update("d", "projD", "done", now=4.0)

    agg = r.aggregate()
    assert agg["u"] == 1
    assert agg["r"] == 2
    assert agg["d"] == 1
    assert agg["i"] == 0
    # most urgent is needs_input -> projC
    assert agg["top"] == "projC"
    # first session entry is the most urgent
    assert agg["sessions"][0] == {"project": "projC", "state": NEEDS_INPUT}
    # done outranks running
    assert agg["sessions"][1] == {"project": "projD", "state": DONE}

def test_aggregate_empty():
    r = SessionRegistry()
    agg = r.aggregate()
    assert agg == {"u": 0, "r": 0, "d": 0, "i": 0, "top": "", "sessions": []}

def test_aggregate_truncates_to_max():
    r = SessionRegistry()
    for n in range(8):
        r.update(f"s{n}", f"p{n}", "running", now=float(n))
    agg = r.aggregate(max_sessions=5)
    assert len(agg["sessions"]) == 5
    # most recent running first (last_seen desc within same state)
    assert agg["sessions"][0]["project"] == "p7"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd daemon && python -m pytest tests/test_aggregator.py -v`
Expected: FAIL with `AttributeError: 'SessionRegistry' object has no attribute 'aggregate'`.

- [ ] **Step 3: Write minimal implementation**

Add to `SessionRegistry` in `daemon/aggregator.py`:

```python
    def aggregate(self, max_sessions=5):
        counts = {IDLE: 0, RUNNING: 0, DONE: 0, NEEDS_INPUT: 0}
        for s in self._sessions.values():
            counts[s["state"]] += 1
        ordered = sorted(
            self._sessions.values(),
            key=lambda s: (s["state"], s["last_seen"]),
            reverse=True,
        )
        top = ordered[0]["project"] if ordered else ""
        return {
            "u": counts[NEEDS_INPUT],
            "r": counts[RUNNING],
            "d": counts[DONE],
            "i": counts[IDLE],
            "top": top,
            "sessions": [
                {"project": s["project"], "state": s["state"]}
                for s in ordered[:max_sessions]
            ],
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd daemon && python -m pytest tests/test_aggregator.py -v`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Commit**

```bash
git add daemon/aggregator.py daemon/tests/test_aggregator.py
git commit -m "feat(daemon): aggregate counts, top, ordered session list"
```

---

### Task 3: Stale-session garbage collection

**Files:**
- Modify: `daemon/aggregator.py`
- Modify: `daemon/tests/test_aggregator.py`

**Interfaces:**
- Consumes: `SessionRegistry`.
- Produces: `SessionRegistry.gc(now: float, idle_timeout: float) -> list[str]` removes sessions whose `now - last_seen > idle_timeout` and returns the removed session ids.

- [ ] **Step 1: Write the failing test**

Append to `daemon/tests/test_aggregator.py`:

```python
def test_gc_removes_stale_only():
    r = SessionRegistry()
    r.update("old", "p1", "running", now=0.0)
    r.update("fresh", "p2", "running", now=100.0)
    removed = r.gc(now=200.0, idle_timeout=150.0)
    assert removed == ["old"]
    assert "old" not in r._sessions
    assert "fresh" in r._sessions
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd daemon && python -m pytest tests/test_aggregator.py::test_gc_removes_stale_only -v`
Expected: FAIL with `AttributeError: ... has no attribute 'gc'`.

- [ ] **Step 3: Write minimal implementation**

Add to `SessionRegistry`:

```python
    def gc(self, now, idle_timeout):
        stale = [
            sid for sid, s in self._sessions.items()
            if now - s["last_seen"] > idle_timeout
        ]
        for sid in stale:
            del self._sessions[sid]
        return stale
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd daemon && python -m pytest tests/test_aggregator.py -v`
Expected: PASS (all 5 tests).

- [ ] **Step 5: Commit**

```bash
git add daemon/aggregator.py daemon/tests/test_aggregator.py
git commit -m "feat(daemon): stale-session garbage collection"
```

---

### Task 4: Event body handling (HTTP-payload → aggregate)

**Files:**
- Create: `daemon/events.py`
- Create: `daemon/tests/test_events.py`

**Interfaces:**
- Consumes: `SessionRegistry`.
- Produces:
  - `project_from_cwd(cwd: str) -> str` — basename of cwd, or `"?"` if empty.
  - `handle_event_body(registry: SessionRegistry, raw: bytes, now: float) -> dict` — parses JSON `{session_id, event, cwd?, project?}`, updates the registry, returns `registry.aggregate()`. Uses explicit `project` if present, else derives from `cwd`. Raises `ValueError`/`KeyError`/`json.JSONDecodeError` on malformed input.

- [ ] **Step 1: Write the failing test**

Create `daemon/tests/test_events.py`:

```python
import json
from aggregator import SessionRegistry, RUNNING
from events import handle_event_body, project_from_cwd

def test_project_from_cwd():
    assert project_from_cwd("/Users/me/Websites/claude-watchh") == "claude-watchh"
    assert project_from_cwd("/Users/me/Websites/claude-watchh/") == "claude-watchh"
    assert project_from_cwd("") == "?"

def test_handle_event_body_updates_and_returns_aggregate():
    r = SessionRegistry()
    raw = json.dumps({
        "session_id": "s1",
        "event": "running",
        "cwd": "/Users/me/proj-x",
    }).encode()
    agg = handle_event_body(r, raw, now=10.0)
    assert agg["r"] == 1
    assert agg["top"] == "proj-x"
    assert r._sessions["s1"]["state"] == RUNNING

def test_handle_event_body_explicit_project_wins():
    r = SessionRegistry()
    raw = json.dumps({"session_id": "s1", "event": "done",
                      "cwd": "/a/b", "project": "override"}).encode()
    agg = handle_event_body(r, raw, now=1.0)
    assert agg["top"] == "override"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd daemon && python -m pytest tests/test_events.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'events'`.

- [ ] **Step 3: Write minimal implementation**

Create `daemon/events.py`:

```python
"""HTTP event-body parsing. Pure (mutates the passed registry); no IO/BLE."""
import json
import os
from aggregator import SessionRegistry


def project_from_cwd(cwd):
    base = os.path.basename((cwd or "").rstrip("/"))
    return base or "?"


def handle_event_body(registry, raw, now):
    data = json.loads(raw)
    session_id = data["session_id"]
    event = data["event"]
    project = data.get("project") or project_from_cwd(data.get("cwd", ""))
    registry.update(session_id, project, event, now)
    return registry.aggregate()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd daemon && python -m pytest tests/test_events.py -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add daemon/events.py daemon/tests/test_events.py
git commit -m "feat(daemon): event-body parsing to aggregate"
```

---

### Task 5: Daemon runtime — HTTP server, debounce, `--mock` output

**Files:**
- Create: `daemon/claude_watch_daemon.py`
- Create: `daemon/config.example.toml`
- Create: `daemon/tests/test_mock_end_to_end.py`

**Interfaces:**
- Consumes: `SessionRegistry` (Task 1-3), `handle_event_body` (Task 4).
- Produces:
  - `class AppState` holding `registry`, `latest_payload`, `dirty` (asyncio.Event), `loop`.
  - `make_handler(state, idle_timeout) -> BaseHTTPRequestHandler subclass` — on `POST /event`, GC then `handle_event_body`, store `latest_payload`, signal `dirty` thread-safely, respond `204`. Malformed body → `400`.
  - `async def pusher(state, writer, debounce)` — waits for `dirty`, debounces, calls `await writer(payload)`.
  - `async def mock_writer(payload)` — prints `json.dumps(payload)` on one line and flushes.
  - `def main()` — argparse: `--mock`, `--scan`, `--port`, `--idle-timeout`, `--debounce`, `--address`, `--config`.

- [ ] **Step 1: Write the failing integration test**

Create `daemon/tests/test_mock_end_to_end.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd daemon && python -m pytest tests/test_mock_end_to_end.py -v`
Expected: FAIL (daemon file does not exist / no payloads).

- [ ] **Step 3: Write the daemon**

Create `daemon/config.example.toml`:

```toml
# Copy to config.toml (gitignored). `--scan` will fill in `address`.
port = 7459
idle_timeout = 900
debounce = 0.25
address = ""   # CoreBluetooth UUID (macOS) of the ClaudeWatch device
```

Create `daemon/claude_watch_daemon.py`:

```python
#!/usr/bin/env python3
"""Claude Watcher daemon: collects hook events and pushes status over BLE.

Runs three things in one process:
  - a localhost HTTP server (hooks POST events here)
  - an aggregator (pure, in aggregator.py)
  - a BLE writer that pushes the latest aggregate to the watch (or prints, in --mock)
"""
import argparse
import asyncio
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from aggregator import SessionRegistry
from events import handle_event_body

DEVICE_NAME = "ClaudeWatch"
SERVICE_UUID = "c1a0de00-0001-4a00-b000-000000000001"
STATUS_UUID = "c1a0de00-0002-4a00-b000-000000000002"


class AppState:
    def __init__(self):
        self.registry = SessionRegistry()
        self.latest_payload = None
        self.dirty = None   # asyncio.Event, set in main()
        self.loop = None


def make_handler(state, idle_timeout):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_POST(self):
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length)
            now = time.time()
            try:
                state.registry.gc(now, idle_timeout)
                payload = handle_event_body(state.registry, raw, now)
            except Exception:
                self.send_response(400)
                self.end_headers()
                return
            state.latest_payload = payload
            state.loop.call_soon_threadsafe(state.dirty.set)
            self.send_response(204)
            self.end_headers()

    return Handler


def start_http(state, port, idle_timeout):
    server = ThreadingHTTPServer(("127.0.0.1", port), make_handler(state, idle_timeout))
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()
    print(f"[daemon] listening on 127.0.0.1:{port}", file=sys.stderr)
    return server


async def pusher(state, writer, debounce):
    while True:
        await state.dirty.wait()
        state.dirty.clear()
        await asyncio.sleep(debounce)
        payload = state.latest_payload
        if payload is not None:
            try:
                await writer(payload)
            except Exception as e:
                print(f"[daemon] write failed: {e}", file=sys.stderr)


async def mock_writer(payload):
    print(json.dumps(payload), flush=True)


def build_arg_parser():
    p = argparse.ArgumentParser(description="Claude Watcher daemon")
    p.add_argument("--mock", action="store_true", help="print payloads instead of BLE")
    p.add_argument("--scan", action="store_true", help="scan for the watch and exit")
    p.add_argument("--port", type=int, default=7459)
    p.add_argument("--idle-timeout", type=float, default=900.0)
    p.add_argument("--debounce", type=float, default=0.25)
    p.add_argument("--address", default="", help="BLE address/UUID of the watch")
    p.add_argument("--config", default="config.toml")
    return p


async def run(args, writer):
    state = AppState()
    state.loop = asyncio.get_running_loop()
    state.dirty = asyncio.Event()
    start_http(state, args.port, args.idle_timeout)
    await pusher(state, writer, args.debounce)


def main():
    args = build_arg_parser().parse_args()
    if args.scan:
        from ble import scan_and_report
        asyncio.run(scan_and_report())
        return
    if args.mock:
        asyncio.run(run(args, mock_writer))
        return
    # real BLE path (Task 6)
    from ble import make_ble_writer
    asyncio.run(_run_ble(args))


async def _run_ble(args):
    from ble import make_ble_writer
    writer = await make_ble_writer(args)
    await run(args, writer)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd daemon && python -m pytest tests/test_mock_end_to_end.py -v`
Expected: PASS.

- [ ] **Step 5: Run the full daemon suite**

Run: `cd daemon && python -m pytest -v`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add daemon/claude_watch_daemon.py daemon/config.example.toml daemon/tests/test_mock_end_to_end.py
git commit -m "feat(daemon): HTTP server, debounced pusher, --mock end-to-end"
```

---

### Task 6: BLE central — scan, connect, reconnect, write

**Files:**
- Create: `daemon/ble.py`

**Interfaces:**
- Consumes: `SERVICE_UUID`, `STATUS_UUID`, `DEVICE_NAME` (re-declared here to avoid a circular import), args from Task 5.
- Produces:
  - `async def scan_and_report() -> None` — scans ~6s, prints discovered devices, highlights any named `ClaudeWatch`, and writes its address into `config.toml`.
  - `async def make_ble_writer(args) -> Callable[[dict], Awaitable[None]]` — returns an async `writer(payload)` that maintains a connection (connect-on-first-write, reconnect with backoff) and `write_gatt_char(STATUS_UUID, json_bytes, response=False)`.

> Note: This task is verified against hardware in Phase 2 (Task 8). For now it must import cleanly and `--scan` must run. Full link-up is proven in Task 8.

- [ ] **Step 1: Write the BLE module**

Create `daemon/ble.py`:

```python
"""BLE central for the Claude Watcher. macOS addresses are CoreBluetooth UUIDs."""
import asyncio
import json
import sys
import tomllib
from pathlib import Path

from bleak import BleakClient, BleakScanner

DEVICE_NAME = "ClaudeWatch"
STATUS_UUID = "c1a0de00-0002-4a00-b000-000000000002"


async def scan_and_report():
    print("[scan] scanning 6s for BLE devices...", file=sys.stderr)
    devices = await BleakScanner.discover(timeout=6.0)
    watch = None
    for d in devices:
        marker = " <-- ClaudeWatch" if (d.name == DEVICE_NAME) else ""
        print(f"  {d.address}  {d.name or '(unnamed)'}{marker}")
        if d.name == DEVICE_NAME:
            watch = d
    if watch is None:
        print("[scan] ClaudeWatch not found. Is the watch powered and advertising?")
        return
    cfg = Path("config.toml")
    cfg.write_text(
        f'port = 7459\nidle_timeout = 900\ndebounce = 0.25\naddress = "{watch.address}"\n'
    )
    print(f"[scan] saved address {watch.address} to {cfg}")


def _load_address(args):
    if args.address:
        return args.address
    cfg = Path(args.config)
    if cfg.exists():
        data = tomllib.loads(cfg.read_text())
        if data.get("address"):
            return data["address"]
    raise SystemExit("No watch address. Run with --scan first, or pass --address.")


async def make_ble_writer(args):
    address = _load_address(args)
    client = BleakClient(address)
    backoff = {"delay": 1.0}

    async def ensure_connected():
        if client.is_connected:
            return
        while True:
            try:
                await client.connect()
                print(f"[ble] connected to {address}", file=sys.stderr)
                backoff["delay"] = 1.0
                return
            except Exception as e:
                print(f"[ble] connect failed ({e}); retry in {backoff['delay']:.0f}s",
                      file=sys.stderr)
                await asyncio.sleep(backoff["delay"])
                backoff["delay"] = min(backoff["delay"] * 2, 30.0)

    async def writer(payload):
        await ensure_connected()
        data = json.dumps(payload, separators=(",", ":")).encode()
        await client.write_gatt_char(STATUS_UUID, data, response=False)

    return writer
```

- [ ] **Step 2: Verify it imports and `--scan` runs**

Run: `cd daemon && python claude_watch_daemon.py --scan`
Expected: prints a device list within ~6s (watch not built yet, so `ClaudeWatch` likely absent — that is fine). No import errors.

- [ ] **Step 3: Commit**

```bash
git add daemon/ble.py
git commit -m "feat(daemon): BLE scan + reconnecting writer"
```

---

## Phase 2 — Minimal BLE firmware + live link

### Task 7: Firmware scaffold — advertise + color-on-write

**Files:**
- Create: `firmware/platformio.ini`
- Create: `firmware/src/main.cpp`

**Interfaces:**
- Consumes: BLE UUIDs / name from Global Constraints.
- Produces: firmware that advertises `ClaudeWatch`, accepts a write to the status characteristic, and paints the whole screen with a color decoded from the first JSON field it can read (`u`/`r`/`d` counts). Proves the BLE link.

- [ ] **Step 1: Confirm the board id**

Run: `pio boards stickc`
Expected: a row for the StickC Plus2. Use that id below (commonly `m5stack-stickc-plus2`). If only `m5stick-c` appears, use that and keep the `board_build`/`board_upload` lines.

- [ ] **Step 2: Create `firmware/platformio.ini`**

```ini
[env:stickcplus2]
platform = espressif32
board = m5stack-stickc-plus2
framework = arduino
monitor_speed = 115200
upload_port = /dev/cu.usbserial-5A6C0505221
monitor_port = /dev/cu.usbserial-5A6C0505221
lib_deps =
    m5stack/M5Unified@^0.1.16
    h2zero/NimBLE-Arduino@^1.4.2
    bblanchon/ArduinoJson@^7.0.0
```

- [ ] **Step 3: Create minimal `firmware/src/main.cpp`**

```cpp
#include <M5Unified.h>
#include <NimBLEDevice.h>
#include <ArduinoJson.h>

static const char* SERVICE_UUID = "c1a0de00-0001-4a00-b000-000000000001";
static const char* STATUS_UUID  = "c1a0de00-0002-4a00-b000-000000000002";

volatile bool g_dirty = false;
volatile bool g_connected = false;
std::string g_rx;

class StatusCb : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c) override {
    g_rx = c->getValue();
    g_dirty = true;
  }
};

class ServerCb : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*) override { g_connected = true; }
  void onDisconnect(NimBLEServer*) override {
    g_connected = false;
    NimBLEDevice::startAdvertising();
  }
};

void setup() {
  auto cfg = M5.config();
  M5.begin(cfg);
  M5.Display.setRotation(0);
  M5.Display.fillScreen(M5.Display.color565(90, 90, 90));
  M5.Display.setTextSize(2);
  M5.Display.setCursor(4, 4);
  M5.Display.print("ClaudeWatch");

  NimBLEDevice::init("ClaudeWatch");
  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCb());
  NimBLEService* svc = server->createService(SERVICE_UUID);
  NimBLECharacteristic* ch = svc->createCharacteristic(
      STATUS_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  ch->setCallbacks(new StatusCb());
  svc->start();
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->start();
}

void loop() {
  M5.update();
  if (g_dirty) {
    g_dirty = false;
    JsonDocument doc;
    if (!deserializeJson(doc, g_rx)) {
      int u = doc["u"] | 0, r = doc["r"] | 0, d = doc["d"] | 0;
      uint16_t color = M5.Display.color565(90, 90, 90);     // idle grey
      if (u > 0)      color = M5.Display.color565(255, 176, 0);  // amber
      else if (d > 0) color = M5.Display.color565(0, 200, 80);   // green
      else if (r > 0) color = M5.Display.color565(0, 120, 255);  // blue
      M5.Display.fillScreen(color);
    }
  }
  delay(20);
}
```

- [ ] **Step 4: Build and flash**

Run: `cd firmware && pio run -t upload`
Expected: compiles, uploads to `/dev/cu.usbserial-5A6C0505221`. Watch boots showing grey screen + "ClaudeWatch".

- [ ] **Step 5: Commit**

```bash
git add firmware/platformio.ini firmware/src/main.cpp
git commit -m "feat(firmware): BLE advertise + color-on-write scaffold"
```

---

### Task 8: Prove the live link (daemon ↔ watch)

**Files:** none (verification task).

**Interfaces:** Consumes Task 6 (`--scan`, BLE writer) + Task 7 (firmware).

- [ ] **Step 1: Scan and save the address**

With the watch powered on, run: `cd daemon && python claude_watch_daemon.py --scan`
Expected: `ClaudeWatch` appears and its address is saved to `daemon/config.toml`.

- [ ] **Step 2: Run the real daemon**

Run: `cd daemon && python claude_watch_daemon.py`
Expected: `[ble] connected to ...` within a few seconds; watch screen stays grey (no events yet).

- [ ] **Step 3: Drive states by hand**

In a second terminal:
```bash
curl -s -m 1 -X POST 127.0.0.1:7459/event -d '{"session_id":"t1","event":"running","cwd":"/x/demo"}'
curl -s -m 1 -X POST 127.0.0.1:7459/event -d '{"session_id":"t1","event":"needs_input","cwd":"/x/demo"}'
curl -s -m 1 -X POST 127.0.0.1:7459/event -d '{"session_id":"t1","event":"done","cwd":"/x/demo"}'
```
Expected: screen turns blue, then amber, then green — one change per command. If colors lag, that is the debounce (0.25s) and is fine.

- [ ] **Step 4: Verify reconnect**

Power-cycle the watch while the daemon runs.
Expected: daemon logs a disconnect + ret ries, then `[ble] connected` again; pushing another curl updates the screen.

- [ ] **Step 5: Commit a note**

```bash
git commit --allow-empty -m "test: verified live daemon<->watch BLE link"
```

---

## Phase 3 — Full firmware (summary, detail, disconnect, self-test)

### Task 9: Summary screen with labels, top project, and counts

**Files:**
- Modify: `firmware/src/main.cpp`

**Interfaces:**
- Consumes: payload `{u,r,d,i,top,sessions}`.
- Produces: a parsed `g_status` struct + `renderSummary()` showing the most-urgent state label, top project, and a counts line.

- [ ] **Step 1: Replace `firmware/src/main.cpp` with the full summary version**

```cpp
#include <M5Unified.h>
#include <NimBLEDevice.h>
#include <ArduinoJson.h>

static const char* SERVICE_UUID = "c1a0de00-0001-4a00-b000-000000000001";
static const char* STATUS_UUID  = "c1a0de00-0002-4a00-b000-000000000002";

enum { ST_IDLE = 0, ST_RUNNING = 1, ST_DONE = 2, ST_NEEDS = 3 };

struct Status {
  int u = 0, r = 0, d = 0, i = 0;
  String top = "";
  int n = 0;
  String proj[5];
  int pstate[5];
  bool valid = false;
} g_status;

volatile bool g_dirty = false;
volatile bool g_connected = false;
std::string g_rx;

class StatusCb : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c) override {
    g_rx = c->getValue();
    g_dirty = true;
  }
};

class ServerCb : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*) override { g_connected = true; }
  void onDisconnect(NimBLEServer*) override {
    g_connected = false;
    NimBLEDevice::startAdvertising();
  }
};

uint16_t stateColor(int st) {
  switch (st) {
    case ST_NEEDS:   return M5.Display.color565(255, 176, 0);
    case ST_DONE:    return M5.Display.color565(0, 200, 80);
    case ST_RUNNING: return M5.Display.color565(0, 120, 255);
    default:         return M5.Display.color565(90, 90, 90);
  }
}

const char* stateLabel(int st) {
  switch (st) {
    case ST_NEEDS:   return "NEEDS INPUT";
    case ST_DONE:    return "DONE";
    case ST_RUNNING: return "RUNNING";
    default:         return "IDLE";
  }
}

int mostUrgent() {
  if (g_status.u > 0) return ST_NEEDS;
  if (g_status.d > 0) return ST_DONE;
  if (g_status.r > 0) return ST_RUNNING;
  return ST_IDLE;
}

void parseStatus(const std::string& s) {
  JsonDocument doc;
  if (deserializeJson(doc, s)) return;
  g_status.u = doc["u"] | 0;
  g_status.r = doc["r"] | 0;
  g_status.d = doc["d"] | 0;
  g_status.i = doc["i"] | 0;
  g_status.top = String((const char*)(doc["top"] | ""));
  g_status.n = 0;
  for (JsonObject o : doc["sessions"].as<JsonArray>()) {
    if (g_status.n >= 5) break;
    g_status.proj[g_status.n] = String((const char*)(o["project"] | "?"));
    g_status.pstate[g_status.n] = o["state"] | 0;
    g_status.n++;
  }
  g_status.valid = true;
}

void renderSummary() {
  int st = mostUrgent();
  uint16_t bg = stateColor(st);
  M5.Display.fillScreen(bg);
  M5.Display.setTextColor(TFT_BLACK, bg);
  M5.Display.setTextSize(2);
  M5.Display.setCursor(6, 10);
  M5.Display.print(stateLabel(st));
  M5.Display.setCursor(6, 48);
  M5.Display.print(g_status.top);
  M5.Display.setTextSize(2);
  M5.Display.setCursor(6, 206);
  M5.Display.printf("R%d N%d D%d", g_status.r, g_status.u, g_status.d);
}

void setup() {
  auto cfg = M5.config();
  M5.begin(cfg);
  M5.Display.setRotation(0);
  renderSummary();

  NimBLEDevice::init("ClaudeWatch");
  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCb());
  NimBLEService* svc = server->createService(SERVICE_UUID);
  NimBLECharacteristic* ch = svc->createCharacteristic(
      STATUS_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  ch->setCallbacks(new StatusCb());
  svc->start();
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->start();
}

void loop() {
  M5.update();
  if (g_dirty) {
    g_dirty = false;
    parseStatus(g_rx);
    renderSummary();
  }
  delay(20);
}
```

- [ ] **Step 2: Build, flash, verify**

Run: `cd firmware && pio run -t upload`
Then push events (daemon running):
```bash
curl -s -m 1 -X POST 127.0.0.1:7459/event -d '{"session_id":"a","event":"running","cwd":"/x/projA"}'
curl -s -m 1 -X POST 127.0.0.1:7459/event -d '{"session_id":"b","event":"needs_input","cwd":"/x/projB"}'
```
Expected: amber screen, label `NEEDS INPUT`, top `projB`, counts line `R1 N1 D0`.

- [ ] **Step 3: Commit**

```bash
git add firmware/src/main.cpp
git commit -m "feat(firmware): summary screen with label, top project, counts"
```

---

### Task 10: Detail view + button navigation

**Files:**
- Modify: `firmware/src/main.cpp`

**Interfaces:**
- Consumes: `g_status.sessions`, `renderSummary()`.
- Produces: a `g_view` toggle (`0`=summary, `1`=detail), `renderDetail()` listing `project: state`, Button A → detail, Button B → summary.

- [ ] **Step 1: Add view state + detail renderer**

Add after `renderSummary()` in `firmware/src/main.cpp`:

```cpp
int g_view = 0;  // 0 = summary, 1 = detail

void renderDetail() {
  M5.Display.fillScreen(TFT_BLACK);
  M5.Display.setTextColor(TFT_WHITE, TFT_BLACK);
  M5.Display.setTextSize(2);
  M5.Display.setCursor(4, 4);
  M5.Display.print("Sessions");
  int y = 36;
  for (int k = 0; k < g_status.n; k++) {
    M5.Display.setTextColor(stateColor(g_status.pstate[k]), TFT_BLACK);
    M5.Display.setCursor(4, y);
    M5.Display.printf("%s:%s", g_status.proj[k].c_str(),
                      stateLabel(g_status.pstate[k]));
    y += 34;
  }
  if (g_status.n == 0) {
    M5.Display.setTextColor(TFT_WHITE, TFT_BLACK);
    M5.Display.setCursor(4, y);
    M5.Display.print("(none)");
  }
}

void render() {
  if (g_view == 1) renderDetail();
  else renderSummary();
}
```

- [ ] **Step 2: Wire buttons + use `render()` in `loop()`**

Replace the body of `loop()` with:

```cpp
void loop() {
  M5.update();
  if (M5.BtnA.wasPressed()) { g_view = 1; render(); }
  if (M5.BtnB.wasPressed()) { g_view = 0; render(); }
  if (g_dirty) {
    g_dirty = false;
    parseStatus(g_rx);
    render();
  }
  delay(20);
}
```

- [ ] **Step 3: Build, flash, verify**

Run: `cd firmware && pio run -t upload`
With several sessions pushed, press Button A.
Expected: screen lists each `project:STATE` color-coded; Button B returns to the color summary.

- [ ] **Step 4: Commit**

```bash
git add firmware/src/main.cpp
git commit -m "feat(firmware): detail view + button navigation"
```

---

### Task 11: Disconnect screen, needs-input flash, self-test

**Files:**
- Modify: `firmware/src/main.cpp`

**Interfaces:**
- Consumes: `g_connected`, `mostUrgent()`, `render()`.
- Produces: a dim-red disconnected screen, a one-shot white flash when entering `needs_input`, and a boot self-test (hold Button B) that cycles all states.

- [ ] **Step 1: Add disconnect render + flash tracking**

Add after `render()`:

```cpp
int g_lastUrgent = -1;
bool g_wasConnected = true;

void renderDisconnected() {
  M5.Display.fillScreen(M5.Display.color565(80, 0, 0));
  M5.Display.setTextColor(TFT_WHITE, M5.Display.color565(80, 0, 0));
  M5.Display.setTextSize(2);
  M5.Display.setCursor(6, 100);
  M5.Display.print("disconnected");
}

void flashNeedsInput() {
  M5.Display.fillScreen(TFT_WHITE);
  delay(120);
}

void selfTest() {
  int seq[] = {ST_IDLE, ST_RUNNING, ST_DONE, ST_NEEDS};
  for (int k = 0; k < 4; k++) {
    uint16_t bg = stateColor(seq[k]);
    M5.Display.fillScreen(bg);
    M5.Display.setTextColor(TFT_BLACK, bg);
    M5.Display.setTextSize(2);
    M5.Display.setCursor(6, 110);
    M5.Display.print(stateLabel(seq[k]));
    delay(700);
  }
}
```

- [ ] **Step 2: Run self-test on boot when Button B is held**

In `setup()`, immediately after `M5.Display.setRotation(0);` add:

```cpp
  M5.update();
  if (M5.BtnB.isPressed()) selfTest();
```

- [ ] **Step 3: Handle connection transitions + flash in `loop()`**

Replace the body of `loop()` with:

```cpp
void loop() {
  M5.update();

  if (g_connected != g_wasConnected) {
    g_wasConnected = g_connected;
    if (g_connected) render();
    else renderDisconnected();
  }

  if (M5.BtnA.wasPressed()) { g_view = 1; render(); }
  if (M5.BtnB.wasPressed()) { g_view = 0; render(); }

  if (g_dirty) {
    g_dirty = false;
    parseStatus(g_rx);
    int urgent = mostUrgent();
    if (urgent == ST_NEEDS && g_lastUrgent != ST_NEEDS && g_view == 0) {
      flashNeedsInput();
    }
    g_lastUrgent = urgent;
    if (g_connected) render();
  }
  delay(20);
}
```

- [ ] **Step 4: Build, flash, verify all three behaviors**

Run: `cd firmware && pio run -t upload`
- Hold Button B during boot → screen cycles grey→blue→green→amber.
- Push a `needs_input` event from summary view → brief white flash, then amber.
- Stop the daemon (or power-cycle nothing, just kill daemon) → after BLE drops, screen shows dim-red `disconnected`.

- [ ] **Step 5: Commit**

```bash
git add firmware/src/main.cpp
git commit -m "feat(firmware): disconnect screen, needs-input flash, self-test"
```

---

## Phase 4 — Hooks + install + end-to-end

### Task 12: Claude Code hooks + install script + full E2E

**Files:**
- Create: `hooks/settings.snippet.json`
- Create: `hooks/install.sh`
- Create: `README.md`

**Interfaces:**
- Consumes: the running daemon on `127.0.0.1:7459`.
- Produces: hook entries that POST events for `Notification`, `Stop`, `UserPromptSubmit`, `PreToolUse`, `SessionEnd`, plus an installer that merges them into `~/.claude/settings.json`.

- [ ] **Step 1: Create `hooks/settings.snippet.json`**

Each hook reads the hook JSON from stdin, extracts `session_id` and `cwd` with a tiny inline Python, and POSTs the mapped event. The `python3 - <<'PY'` block is given `$EVENT` via the environment.

```json
{
  "hooks": {
    "Notification": [
      { "hooks": [ { "type": "command", "command": "EVENT=needs_input python3 -c 'import sys,os,json,urllib.request as u; d=json.load(sys.stdin); body=json.dumps({\"session_id\":d.get(\"session_id\",\"?\"),\"cwd\":d.get(\"cwd\",\"\"),\"event\":os.environ[\"EVENT\"]}).encode(); req=u.Request(\"http://127.0.0.1:7459/event\",data=body,method=\"POST\");\nimport socket;\ntry: u.urlopen(req,timeout=1)\nexcept Exception: pass' 2>/dev/null || true" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "EVENT=done python3 -c 'import sys,os,json,urllib.request as u; d=json.load(sys.stdin); body=json.dumps({\"session_id\":d.get(\"session_id\",\"?\"),\"cwd\":d.get(\"cwd\",\"\"),\"event\":os.environ[\"EVENT\"]}).encode(); req=u.Request(\"http://127.0.0.1:7459/event\",data=body,method=\"POST\")\ntry: u.urlopen(req,timeout=1)\nexcept Exception: pass' 2>/dev/null || true" } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "EVENT=running python3 -c 'import sys,os,json,urllib.request as u; d=json.load(sys.stdin); body=json.dumps({\"session_id\":d.get(\"session_id\",\"?\"),\"cwd\":d.get(\"cwd\",\"\"),\"event\":os.environ[\"EVENT\"]}).encode(); req=u.Request(\"http://127.0.0.1:7459/event\",data=body,method=\"POST\")\ntry: u.urlopen(req,timeout=1)\nexcept Exception: pass' 2>/dev/null || true" } ] }
    ],
    "PreToolUse": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "EVENT=running python3 -c 'import sys,os,json,urllib.request as u; d=json.load(sys.stdin); body=json.dumps({\"session_id\":d.get(\"session_id\",\"?\"),\"cwd\":d.get(\"cwd\",\"\"),\"event\":os.environ[\"EVENT\"]}).encode(); req=u.Request(\"http://127.0.0.1:7459/event\",data=body,method=\"POST\")\ntry: u.urlopen(req,timeout=1)\nexcept Exception: pass' 2>/dev/null || true" } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "EVENT=ended python3 -c 'import sys,os,json,urllib.request as u; d=json.load(sys.stdin); body=json.dumps({\"session_id\":d.get(\"session_id\",\"?\"),\"cwd\":d.get(\"cwd\",\"\"),\"event\":os.environ[\"EVENT\"]}).encode(); req=u.Request(\"http://127.0.0.1:7459/event\",data=body,method=\"POST\")\ntry: u.urlopen(req,timeout=1)\nexcept Exception: pass' 2>/dev/null || true" } ] }
    ]
  }
}
```

- [ ] **Step 2: Create `hooks/install.sh` (merge into settings.json)**

```bash
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
```

- [ ] **Step 3: Verify hook JSON is valid before installing**

Run: `python3 -c "import json; json.load(open('hooks/settings.snippet.json')); print('valid')"`
Expected: `valid`.

- [ ] **Step 4: Install hooks and verify merge**

Run: `bash hooks/install.sh`
Then: `python3 -c "import json; print(list(json.load(open(__import__('os').path.expanduser('~/.claude/settings.json'))['hooks'].keys())))"`
Expected: includes `Notification`, `Stop`, `UserPromptSubmit`, `PreToolUse`, `SessionEnd`.

- [ ] **Step 5: Full end-to-end test**

1. Watch powered on; `cd daemon && python claude_watch_daemon.py` (connects).
2. Open a **new** Claude Code terminal in some project and send a prompt.
   Expected: watch turns blue (RUNNING), top shows that project.
3. Let Claude finish.
   Expected: watch turns green (DONE).
4. Trigger a permission prompt (e.g. a command needing approval).
   Expected: watch flashes then turns amber (NEEDS INPUT).
5. Open a second Claude terminal in a different project and prompt it.
   Expected: counts line reflects both; Button A lists both projects.

- [ ] **Step 6: Write `README.md`**

```markdown
# Claude Watcher

A wearable M5StickC Plus2 that shows the live state of every Claude Code
agent across your terminals over Bluetooth LE.

## Setup
1. Flash the watch: `cd firmware && pio run -t upload`
2. Daemon deps: `cd daemon && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt`
3. Pair: `python claude_watch_daemon.py --scan` (saves the watch address to config.toml)
4. Install hooks: `bash hooks/install.sh`
5. Run: `cd daemon && source .venv/bin/activate && python claude_watch_daemon.py`

## States
- blue = running, green = done, amber = needs input, grey = idle, dim red = BLE disconnected
- Button A: per-session detail; Button B: back to summary
- Hold Button B at boot for a self-test color cycle

## Architecture
hooks (curl, 1s timeout) -> daemon (127.0.0.1:7459, aggregates) -> BLE -> watch
```

- [ ] **Step 7: Commit**

```bash
git add hooks/ README.md
git commit -m "feat: Claude Code hooks, installer, README, end-to-end"
```

---

## Self-Review (completed during planning)

- **Spec coverage:** transport=BLE (Tasks 6-8), daemon-in-the-middle (Tasks 5-6), event server (Task 5), aggregator + GC (Tasks 1-3), 4-state model + colors (Tasks 7,9,11), screen-only/no buzzer (deferred per spec), most-urgent+counts summary (Task 9), detail view + buttons (Task 10), both running signals + debounce (hooks Task 12 + debounce Task 5), fire-and-forget 1s hooks (Task 12), payload format (Tasks 5,6,9), disconnect handling (Tasks 6,11), stale GC (Tasks 3,5), first-run pairing (Task 6), `--mock` testing (Task 5), self-test mode (Task 11), file layout (all). Covered.
- **Placeholder scan:** no TBD/TODO; every code step shows complete content.
- **Type consistency:** `SessionRegistry.update/aggregate/gc`, `handle_event_body`, `project_from_cwd`, `make_ble_writer`, `scan_and_report`, payload keys `u/r/d/i/top/sessions`, state ints, BLE UUIDs/name all consistent across daemon and firmware.
