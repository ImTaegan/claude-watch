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
