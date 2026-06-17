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
hooks (python3/urllib, 1s timeout) -> daemon (127.0.0.1:7459, aggregates) -> BLE -> watch
