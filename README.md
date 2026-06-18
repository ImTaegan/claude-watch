# Claude Watcher

Shows the live state of every Claude Code agent across your terminals — on a
wearable M5StickC Plus2 over Bluetooth LE, and/or in a native macOS menu bar
app. Both read the same daemon, so they work together or independently.

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

## Mac menu bar app

A native menu bar app (`macapp/`) shows every active Claude agent across all
projects, styled like Control Center. It reads the same daemon as the watch.

![Panel](macapp/docs/panel.png)

Build and run:

```bash
cd macapp && ./build.sh && open ClaudeWatchBar.app
```

The app polls `GET http://127.0.0.1:7459/status` once per second and shows
"daemon offline" when it can't reach the daemon. The daemon serves this endpoint
with or without the hardware watch — `python claude_watch_daemon.py --mock` is
enough to drive the menu bar app on its own. The menu bar icon reflects the
worst-case state (a bell when any agent needs input), and the dropdown lists
each agent with a status dot, project name, and relative time.

Requires macOS 13+. The `build.sh` script compiles with SwiftPM and assembles a
menu-bar-only (`LSUIElement`) `.app` bundle — no Xcode GUI needed.

## Architecture
hooks (python3/urllib, 1s timeout) -> daemon (127.0.0.1:7459, aggregates)
  -> BLE -> watch
  -> GET /status (1s poll) -> macOS menu bar app
