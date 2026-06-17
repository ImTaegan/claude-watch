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
