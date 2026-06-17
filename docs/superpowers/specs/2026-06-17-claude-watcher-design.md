# Claude Watcher — Design Spec

**Date:** 2026-06-17
**Status:** Approved for planning
**Hardware:** M5StickC Plus2 (ESP32-PICO-V3-02, 1.14" 135×240 TFT, buttons A/B/PWR, passive buzzer, USB-C). Serial port observed at `/dev/cu.usbserial-5A6C0505221`.

## Goal

A wearable that alerts the user to the state of every Claude Code agent running across all terminals on their laptop: whether an agent is running, has finished (stopped), or needs the user's input. The watch is worn off-tether; signals travel over Bluetooth LE.

## Non-goals (v1)

- No buzzer/sound alerts (screen-only). Deferred; firmware leaves a clean hook to add a soft beep later.
- No remote/over-internet operation. Same-room BLE range only.
- No two-way control (the watch displays; it does not send commands back to Claude).
- No multi-laptop support. One daemon, one laptop.

## Architecture

Three pieces:

```
Claude Code hooks  ──HTTP POST──▶  Laptop daemon  ──BLE write──▶  StickC Plus2
(per terminal)      127.0.0.1      (Python+bleak)    GATT char      (firmware)
```

Rationale for the daemon-in-the-middle: BLE wants a single persistent central↔peripheral connection. Claude Code hooks are short-lived processes that fire many times per second across multiple sessions; they cannot each own a BLE connection. The daemon is the only process that talks BLE. Hooks just POST events to it over localhost.

### 1. Watch firmware

- **Stack:** PlatformIO + Arduino framework + `M5Unified` (display/buttons/power) + `NimBLE-Arduino` (low-memory BLE stack).
- **Role:** BLE **peripheral**. Advertises one service (`ClaudeWatch`) exposing one writable + notifiable **status characteristic**.
- **Behavior:** On each status write, parse the payload and re-render. Button A cycles into a per-session detail view; Button B returns to the summary. On BLE disconnect, show a "disconnected" screen and keep advertising for reconnect.
- **Self-test mode:** a compile-time/button-held mode that cycles through all states for visual verification without the daemon.

### 2. Laptop daemon (Python)

Single long-running process with three concerns:

- **Event server:** minimal HTTP listener on `127.0.0.1:7459`. Accepts `POST /event` with a JSON body. Localhost-only bind.
- **Session registry + aggregator** (`aggregator.py`, hardware-free, unit-tested):
  - Tracks each `session_id → { project, state, last_seen }`.
  - `project` derived from the basename of the session's `cwd`.
  - Computes the **most-urgent** state across all live sessions plus per-state **counts**.
  - **Garbage-collects** sessions whose `last_seen` exceeds an idle timeout (default 15 min) so crashed terminals don't linger.
- **BLE central** (`bleak`): scans for the watch by saved MAC (from config), connects, **auto-reconnects with exponential backoff**, negotiates MTU large enough for the payload, and writes the status characteristic whenever the aggregate changes (**debounced**, default 250 ms, so chatty `PreToolUse` events don't spam BLE).
- **`--mock` mode:** prints the payload it *would* write to BLE instead of connecting to hardware. Lets the entire hook→daemon→aggregate→payload chain be exercised with zero hardware.

### 3. Claude Code hooks (`~/.claude/settings.json`)

Each hook is a **fire-and-forget** `curl` with a hard **1-second timeout** so it can never block the agent if the daemon is down:

```
curl -s -m 1 -X POST 127.0.0.1:7459/event -d '{...}' >/dev/null 2>&1 || true
```

Hook → event mapping:

| Hook | Reported event | Resulting state |
|------|----------------|-----------------|
| `Notification` | `needs_input` | needs_input |
| `Stop` | `done` | done |
| `UserPromptSubmit` | `running` | running |
| `PreToolUse` (matcher `*`) | `running` | running (keeps long tasks fresh) |
| `SessionEnd` | `ended` | session removed |

`SessionStart` may also fire `running`/`idle` to register the session early. Hook payloads pass `session_id` and `cwd` (from the hook's stdin JSON / environment) so the daemon can label and track per-session.

## State model

Four states with a fixed urgency order:

```
needs_input (3)  >  done (2)  >  running (1)  >  idle (0)
```

Screen colors:

| State | Color | Notes |
|-------|-------|-------|
| needs_input | amber | flash briefly on entry |
| done | green | |
| running | blue | |
| idle | grey | |
| (BLE) disconnected | dim red | firmware-local, not a session state |

**Summary screen (default):** large color block for the most-urgent state + a counts line, e.g. `▶2  need:1  done:1`.
**Detail screen (Button A):** per-session list — `project: state`, paged by button.

## Data flow

1. A hook fires in some terminal.
2. `curl -m 1 POST 127.0.0.1:7459/event {session_id, cwd, event}`.
3. Daemon updates the registry entry for that `session_id`.
4. Aggregator recomputes most-urgent + counts.
5. If the aggregate changed, debounce (~250 ms) then BLE-write a compact payload.
6. Watch parses and re-renders.

### Wire payload

Compact JSON, ~40 bytes, MTU negotiated to fit in a single write:

```json
{ "u": 1, "r": 2, "d": 1, "i": 0, "top": "projB" }
```

- `u` = needs_input count, `r` = running, `d` = done, `i` = idle.
- `top` = project name of the most-urgent session (for the summary line).
- Most-urgent state is derived on the watch from whichever count is non-zero highest in urgency order (no need to send it separately).

A small fixed list of recent sessions for the detail view is sent as an extra field when it fits, or via a second characteristic if the payload outgrows one MTU. Default plan: keep detail to the top ~5 sessions in one payload.

## Error handling

- **Daemon down:** hook `curl` times out in 1s and the `|| true` swallows failure — Claude is never blocked or delayed beyond 1s.
- **BLE disconnect:** watch shows the disconnected screen and keeps advertising; daemon retries scan/connect with exponential backoff (cap ~30s).
- **Stale sessions:** GC after idle timeout (default 15 min) so a killed terminal stops counting.
- **First run / pairing:** a `--scan` command lists nearby BLE devices; the user picks the watch and its MAC is saved to a config file (`~/.config/claude-watch/config.toml` or repo-local `daemon/config.toml`).
- **Multiple watches:** connect only to the configured MAC.

## Testing strategy

- **Unit:** `aggregator.py` — state transitions, urgency selection, count math, stale-session GC — all hardware-free.
- **Integration (mock):** run daemon with `--mock`; drive it with scripted/curl events and assert printed payloads. Covers the full hook→daemon→payload path with no watch.
- **Firmware self-test:** on-device mode cycles all states to verify rendering and buttons.
- **Manual end-to-end:** real Claude Code sessions across multiple terminals against the live watch.

## File layout

```
firmware/
  platformio.ini
  src/main.cpp
daemon/
  claude_watch_daemon.py     # entrypoint: event server + BLE central + --mock/--scan
  aggregator.py              # hardware-free session registry + aggregation logic
  config.toml                # saved watch MAC, port, timeouts
  requirements.txt           # bleak, etc.
  tests/
    test_aggregator.py
hooks/
  settings.snippet.json      # hooks block to merge into ~/.claude/settings.json
  install.sh                 # merges hooks, installs deps, prints next steps
docs/
  superpowers/specs/2026-06-17-claude-watcher-design.md
README.md
```

## Build order (daemon-first, de-risked)

1. **Daemon + aggregator in `--mock`.** Event server, registry, aggregation, payload format. Unit + integration tests green. No hardware.
2. **Minimal BLE proof.** Smallest firmware that advertises + accepts a write and changes the screen color; daemon connects and pushes a hardcoded state. Proves the BLE link end-to-end.
3. **Full firmware.** Real rendering, summary + detail screens, buttons, disconnect handling, self-test mode.
4. **Hooks + install.** Wire `~/.claude/settings.json`, install script, full multi-terminal end-to-end test.
5. **(Deferred)** soft buzzer alert.

## Open decisions deferred to later

- Exact color hex values and font sizes (tune on-device).
- Whether detail view needs a second BLE characteristic (only if payload outgrows one MTU).
- How the watch is physically worn (strap vs. clip) — hardware accessory, out of software scope.
