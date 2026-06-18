# Claude Watcher — macOS Menu Bar App

**Date:** 2026-06-18
**Status:** Approved design
**Author:** brainstormed with Claude Code

## Summary

Expand Claude Watcher beyond the hardware watch with a native macOS menu bar
app. It lives in the system status bar (next to WiFi / Control Center / clock)
and, when clicked, shows a live panel of every Claude Code agent currently
active across all projects on the laptop.

The daemon remains the single source of truth. The watch and the Mac app are two
independent consumers of the same aggregated session state.

## Goals

- Glanceable status in the menu bar: know at a glance if any agent needs input.
- A click-down panel listing each active agent with project, state, and a
  relative timestamp.
- Native look that matches the macOS Control Center / WiFi dropdown
  (translucent material, rounded panel, SF Symbol rows, hover highlights).
- Works whether or not the hardware watch is present.
- No changes to the Claude Code hooks (use only data already captured).

## Non-Goals

- Last-tool-used / last-prompt-snippet per agent. This needs richer hook
  payloads and is left as a clean follow-up.
- Interacting with agents from the panel (focusing a terminal, sending input).
  Read-only for v1.
- Windows / Linux tray support.

## Architecture

```
Claude hooks ──POST /event──► daemon (SessionRegistry)
                                 ├──BLE push──► watch            (existing)
                                 └──GET /status──► Mac menu bar app (new)
```

- The daemon already runs a localhost HTTP server, a pure `SessionRegistry`
  aggregator, and a BLE pusher.
- The Mac app polls `GET http://127.0.0.1:7459/status` about once per second via
  `URLSession`, decodes the JSON, and updates SwiftUI state.
- Polling (not push) is chosen deliberately: localhost, tiny payload, 1s already
  feels live. No websocket/SSE machinery.
- The watch and the Mac app operate simultaneously and independently.

## Components

### 1. Daemon changes (`daemon/`)

**`SessionRegistry.status(now)`** — new method in `aggregator.py`, alongside the
existing `aggregate()`. Returns a richer, human-facing payload:

```json
{
  "counts": { "needs_input": 1, "running": 2, "done": 0, "idle": 1 },
  "agents": [
    { "project": "compile-me", "state": 3, "age_seconds": 4.2 },
    { "project": "claude-watchh", "state": 1, "age_seconds": 12.0 }
  ]
}
```

- `state` uses the existing integer constants (IDLE=0, RUNNING=1, DONE=2,
  NEEDS_INPUT=3) so the Swift side maps them directly.
- `age_seconds` = `now - last_seen`, computed at read time.
- Agents are sorted by the same priority the watch uses: state desc, then
  `last_seen` desc (needs-input first, then running, etc.).
- The compact BLE payload from `aggregate()` is left untouched, so the watch is
  unaffected.

**`GET /status`** — new branch in the HTTP handler in
`claude_watch_daemon.py`. Under `state.lock`, runs `gc(now, idle_timeout)`, then
returns `json.dumps(state.registry.status(now))` with `Content-Type:
application/json` and an `Access-Control` header is not needed (same-origin not
relevant for a native client). Responds 200 with the body. `do_POST` is
unchanged.

**Serve HTTP before / without BLE.** Today `_run_ble()` awaits
`make_ble_writer(args)` *before* calling `run()`, which starts the HTTP server.
If no watch is present this blocks, so the Mac app would never get a response.
Restructure so the HTTP server starts first and the BLE connection is
established in a background task. This also stops the watch path from hanging on
a missing device. The pusher waits for a writer to become available (or runs a
no-op writer until BLE connects).

### 2. Mac menu bar app (`macapp/`)

A SwiftUI app using `MenuBarExtra` in `.window` style (real SwiftUI panel, not
an `NSMenu`). `LSUIElement` so there is no Dock icon.

Files:
- `macapp/Package.swift` — SwiftPM manifest, executable target
  `ClaudeWatchBar`, macOS 13+ (MenuBarExtra requires 13).
- `macapp/Sources/ClaudeWatchBar/ClaudeWatchBarApp.swift` — `@main` App,
  `MenuBarExtra` with `.menuBarExtraStyle(.window)`.
- `macapp/Sources/ClaudeWatchBar/StatusModel.swift` — `ObservableObject` that
  polls the daemon and publishes the decoded state + connection status.
- `macapp/Sources/ClaudeWatchBar/StatusDTO.swift` — `Codable` types matching the
  `/status` JSON, plus an `AgentState` enum mapping the integer states.
- `macapp/Sources/ClaudeWatchBar/PanelView.swift` — the dropdown panel UI.
- `macapp/build.sh` — runs `swift build -c release`, assembles
  `ClaudeWatchBar.app` (binary + generated `Info.plist` with `LSUIElement` and
  bundle id), prints the path.

UI behavior:
- **Menu bar icon:** an SF Symbol reflecting worst-case state. When any agent is
  `needs_input`, show an attention variant (e.g. filled/orange); otherwise a
  calm glyph. Driven by the polled counts.
- **Panel** (`.background(.ultraThinMaterial)`, rounded corners, padding to
  match Control Center):
  - **Header:** "Claude Agents" + count pills (needs-input, running, done,
    idle) colored consistently with the status dots.
  - **Agent list:** scrollable; one row per agent = colored status dot +
    project name + relative time ("needs input", "running 2m", "idle 5m").
    Relative time formatted from `age_seconds`.
  - **Empty state:** "No active agents".
  - **Footer:** dimmed connection line ("● connected" / "daemon offline" when a
    poll fails) and a Quit button.

State → color/label mapping (shared by dot, pill, icon):
- NEEDS_INPUT → orange, "needs input"
- RUNNING → blue/green, "running"
- DONE → green/check, "done"
- IDLE → gray, "idle"

### 3. Polling & resilience

- `StatusModel` schedules a `Timer` (~1s). On each tick it fetches `/status`.
- On success: decode, set `connected = true`, publish agents/counts.
- On failure (daemon down): set `connected = false`, keep last known list dimmed
  or clear to empty + show "daemon offline" in the footer. Never crash.

## Data flow (end to end)

1. A hook fires in some project → POST `/event` → registry updates.
2. Watch gets the compact BLE push (unchanged).
3. ~1s later the Mac app polls `/status`, the daemon GCs stale sessions and
   returns the rich payload, the panel re-renders.

## Error handling

- Daemon: malformed GET → still return current status (GET has no body to
  parse); any internal error → 500 with empty body, app treats as offline.
- App: network errors and decode errors both flip `connected = false`; the UI
  degrades to "daemon offline" rather than throwing.
- Missing watch no longer blocks the HTTP server.

## Testing

- **Daemon (pytest):**
  - `registry.status(now)` — counts, ordering, `age_seconds` correctness, empty
    registry.
  - GET `/status` endpoint returns valid JSON reflecting posted events
    (extend the mock end-to-end test).
  - Existing tests stay green (BLE payload unchanged).
- **Swift:** a small unit test decoding a sample `/status` JSON into the DTOs
  and mapping states.
- **Manual:** run the daemon in mock mode, run the app, post synthetic events,
  confirm the panel matches and the icon flips on needs-input.

## Project layout after this work

```
macapp/
  Package.swift
  build.sh
  Sources/ClaudeWatchBar/
    ClaudeWatchBarApp.swift
    StatusModel.swift
    StatusDTO.swift
    PanelView.swift
  Tests/ClaudeWatchBarTests/...
daemon/            (aggregator.py + claude_watch_daemon.py touched)
README.md          (new "Mac menu bar app" section)
```

## Build & run

```
# daemon (serves HTTP even without a watch)
cd daemon && source .venv/bin/activate && python claude_watch_daemon.py --mock

# mac app
cd macapp && ./build.sh && open ClaudeWatchBar.app
```
