# Mac Menu Bar App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native macOS menu bar app that shows every active Claude Code agent across all projects, styled like the Control Center / WiFi dropdown, fed by the existing daemon.

**Architecture:** The daemon stays the single source of truth. It gains a `GET /status` endpoint returning rich per-agent JSON. A native Swift `MenuBarExtra` (window style) app polls that endpoint ~1×/sec and renders a translucent SwiftUI panel. Watch and Mac app are independent consumers.

**Tech Stack:** Python 3.14 stdlib (daemon, pytest), Swift 6 / SwiftUI / SwiftPM (menu bar app), bash (bundle build script).

## Global Constraints

- No changes to Claude Code hooks (`hooks/`) — use only data already captured (project + state + timing).
- Daemon must serve HTTP whether or not a watch is configured/present.
- BLE payload shape from `aggregate()` must stay byte-for-byte unchanged (the watch firmware depends on it).
- macOS 13+ (required for `MenuBarExtra(.window)`).
- App connects only to `http://127.0.0.1:7459/status` (loopback).
- State integer constants are fixed: IDLE=0, RUNNING=1, DONE=2, NEEDS_INPUT=3.
- `/status` JSON shape is the contract between daemon and app:
  `{"counts":{"needs_input":N,"running":N,"done":N,"idle":N},"agents":[{"project":str,"state":int,"age_seconds":float}]}`
  agents sorted needs-input → running → done → idle, then most-recent first.

---

### Task 1: Daemon — `SessionRegistry.status(now)`

**Files:**
- Modify: `daemon/aggregator.py` (add `status` method to `SessionRegistry`)
- Test: `daemon/tests/test_aggregator.py` (add cases)

**Interfaces:**
- Consumes: existing `SessionRegistry.update(session_id, project, event, now)` and state constants.
- Produces: `SessionRegistry.status(now: float) -> dict` with the `/status` JSON shape above (Python dict, not serialized).

- [ ] **Step 1: Write the failing tests**

Add to `daemon/tests/test_aggregator.py`:

```python
from aggregator import SessionRegistry


def test_status_counts_and_order():
    r = SessionRegistry()
    r.update("s1", "projA", "running", now=100.0)
    r.update("s2", "projB", "needs_input", now=101.0)
    st = r.status(now=105.0)
    assert st["counts"] == {"needs_input": 1, "running": 1, "done": 0, "idle": 0}
    assert [a["project"] for a in st["agents"]] == ["projB", "projA"]
    assert st["agents"][0]["state"] == 3
    assert st["agents"][0]["age_seconds"] == 4.0
    assert st["agents"][1]["age_seconds"] == 5.0


def test_status_empty():
    st = SessionRegistry().status(now=1.0)
    assert st["agents"] == []
    assert st["counts"] == {"needs_input": 0, "running": 0, "done": 0, "idle": 0}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd daemon && .venv/bin/python -m pytest tests/test_aggregator.py -k status -v`
Expected: FAIL with `AttributeError: 'SessionRegistry' object has no attribute 'status'`

- [ ] **Step 3: Implement `status`**

Add to `SessionRegistry` in `daemon/aggregator.py` (after `aggregate`):

```python
    def status(self, now):
        counts = {IDLE: 0, RUNNING: 0, DONE: 0, NEEDS_INPUT: 0}
        for s in self._sessions.values():
            counts[s["state"]] += 1
        ordered = sorted(
            self._sessions.values(),
            key=lambda s: (s["state"], s["last_seen"]),
            reverse=True,
        )
        return {
            "counts": {
                "needs_input": counts[NEEDS_INPUT],
                "running": counts[RUNNING],
                "done": counts[DONE],
                "idle": counts[IDLE],
            },
            "agents": [
                {
                    "project": s["project"],
                    "state": s["state"],
                    "age_seconds": round(now - s["last_seen"], 1),
                }
                for s in ordered
            ],
        }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd daemon && .venv/bin/python -m pytest tests/test_aggregator.py -v`
Expected: PASS (all aggregator tests, old + new)

- [ ] **Step 5: Commit**

```bash
git add daemon/aggregator.py daemon/tests/test_aggregator.py
git commit -m "feat(daemon): SessionRegistry.status() rich per-agent payload"
```

---

### Task 2: Daemon — `GET /status` endpoint + BLE-optional startup

**Files:**
- Modify: `daemon/claude_watch_daemon.py` (add `do_GET`; make BLE optional)
- Test: `daemon/tests/test_mock_end_to_end.py` (add GET test)

**Interfaces:**
- Consumes: `SessionRegistry.status(now)` from Task 1; existing `AppState`, `make_handler`, `_run_ble`.
- Produces: HTTP `GET /status` → 200 `application/json` body = `registry.status(now)`; daemon serves HTTP even with no watch address.

- [ ] **Step 1: Write the failing test**

Add to `daemon/tests/test_mock_end_to_end.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd daemon && .venv/bin/python -m pytest tests/test_mock_end_to_end.py::test_status_endpoint_reports_agents -v`
Expected: FAIL — GET `/status` returns 501/404 (no `do_GET`), raising `HTTPError`.

- [ ] **Step 3: Add `do_GET` to the handler**

In `daemon/claude_watch_daemon.py`, inside `make_handler`'s `Handler` class, add this method (alongside `do_POST`):

```python
        def do_GET(self):
            if self.path != "/status":
                self.send_response(404)
                self.end_headers()
                return
            now = time.time()
            with state.lock:
                state.registry.gc(now, idle_timeout)
                body = json.dumps(state.registry.status(now)).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd daemon && .venv/bin/python -m pytest tests/test_mock_end_to_end.py -v`
Expected: PASS

- [ ] **Step 5: Make BLE optional so HTTP always serves**

In `daemon/claude_watch_daemon.py`, add a no-op writer near `mock_writer`:

```python
async def noop_writer(payload):
    pass
```

Then change `_run_ble` to fall back when no watch address is configured:

```python
async def _run_ble(args):
    from ble import make_ble_writer
    try:
        writer = await make_ble_writer(args)
    except SystemExit as e:
        print(f"[daemon] {e}; serving HTTP only (no watch)", file=sys.stderr)
        writer = noop_writer
    await run(args, writer)
```

- [ ] **Step 6: Verify the full daemon suite still passes**

Run: `cd daemon && .venv/bin/python -m pytest -v`
Expected: PASS (all tests, BLE payload unchanged)

- [ ] **Step 7: Commit**

```bash
git add daemon/claude_watch_daemon.py daemon/tests/test_mock_end_to_end.py
git commit -m "feat(daemon): GET /status endpoint; serve HTTP without a watch"
```

---

### Task 3: Mac app — SwiftPM scaffold + DTOs + decode test

**Files:**
- Create: `macapp/Package.swift`
- Create: `macapp/Sources/ClaudeWatchKit/StatusDTO.swift`
- Create: `macapp/Tests/ClaudeWatchKitTests/StatusDTOTests.swift`
- Create: `macapp/.gitignore`

**Interfaces:**
- Produces (public, used by Tasks 4–5):
  - `enum AgentState: Int { idle=0, running=1, done=2, needsInput=3 }`, `var label: String`
  - `struct Counts: Codable, Equatable { needsInput, running, done, idle: Int }`
  - `struct Agent: Codable, Equatable { let project: String; let state: Int; let ageSeconds: Double; var agentState: AgentState }`
  - `struct StatusPayload: Codable, Equatable { let counts: Counts; let agents: [Agent] }`
  - Decoder contract: callers use `JSONDecoder` with `.keyDecodingStrategy = .convertFromSnakeCase`.

- [ ] **Step 1: Create the package manifest**

`macapp/Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeWatchBar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ClaudeWatchKit"),
        .executableTarget(name: "ClaudeWatchBar", dependencies: ["ClaudeWatchKit"]),
        .testTarget(name: "ClaudeWatchKitTests", dependencies: ["ClaudeWatchKit"]),
    ]
)
```

- [ ] **Step 2: Create `.gitignore`**

`macapp/.gitignore`:

```
.build/
*.app
```

- [ ] **Step 3: Write the DTOs**

`macapp/Sources/ClaudeWatchKit/StatusDTO.swift`:

```swift
import Foundation

public enum AgentState: Int, Codable, Sendable {
    case idle = 0, running = 1, done = 2, needsInput = 3

    public var label: String {
        switch self {
        case .needsInput: return "needs input"
        case .running: return "running"
        case .done: return "done"
        case .idle: return "idle"
        }
    }
}

public struct Counts: Codable, Equatable, Sendable {
    public var needsInput: Int
    public var running: Int
    public var done: Int
    public var idle: Int

    public init(needsInput: Int = 0, running: Int = 0, done: Int = 0, idle: Int = 0) {
        self.needsInput = needsInput
        self.running = running
        self.done = done
        self.idle = idle
    }
}

public struct Agent: Codable, Equatable, Sendable {
    public let project: String
    public let state: Int
    public let ageSeconds: Double

    public init(project: String, state: Int, ageSeconds: Double) {
        self.project = project
        self.state = state
        self.ageSeconds = ageSeconds
    }

    public var agentState: AgentState { AgentState(rawValue: state) ?? .idle }
}

public struct StatusPayload: Codable, Equatable, Sendable {
    public let counts: Counts
    public let agents: [Agent]

    public init(counts: Counts, agents: [Agent]) {
        self.counts = counts
        self.agents = agents
    }
}
```

- [ ] **Step 4: Write the failing decode test**

`macapp/Tests/ClaudeWatchKitTests/StatusDTOTests.swift`:

```swift
import XCTest
@testable import ClaudeWatchKit

final class StatusDTOTests: XCTestCase {
    func testDecodeStatusPayload() throws {
        let json = """
        {"counts":{"needs_input":1,"running":2,"done":0,"idle":1},
         "agents":[{"project":"compile-me","state":3,"age_seconds":4.2},
                   {"project":"claude-watchh","state":1,"age_seconds":12.0}]}
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let p = try dec.decode(StatusPayload.self, from: json)
        XCTAssertEqual(p.counts, Counts(needsInput: 1, running: 2, done: 0, idle: 1))
        XCTAssertEqual(p.agents.count, 2)
        XCTAssertEqual(p.agents[0].project, "compile-me")
        XCTAssertEqual(p.agents[0].agentState, .needsInput)
        XCTAssertEqual(p.agents[0].ageSeconds, 4.2, accuracy: 0.001)
        XCTAssertEqual(p.agents[1].agentState, .running)
    }

    func testUnknownStateFallsBackToIdle() {
        XCTAssertEqual(Agent(project: "x", state: 99, ageSeconds: 0).agentState, .idle)
    }
}
```

- [ ] **Step 5: Run the test (compiles the package, verifies decode)**

Run: `cd macapp && swift test`
Expected: PASS, 2 tests. (First run also resolves/builds — allow time.)

- [ ] **Step 6: Commit**

```bash
git add macapp/Package.swift macapp/.gitignore macapp/Sources/ClaudeWatchKit/StatusDTO.swift macapp/Tests/ClaudeWatchKitTests/StatusDTOTests.swift
git commit -m "feat(macapp): SwiftPM scaffold + status DTOs with decode test"
```

---

### Task 4: Mac app — polling model

**Files:**
- Create: `macapp/Sources/ClaudeWatchBar/StatusModel.swift`

**Interfaces:**
- Consumes: `StatusPayload`, `Counts`, `Agent`, `AgentState` from `ClaudeWatchKit`.
- Produces: `@MainActor final class StatusModel: ObservableObject` with `@Published var payload: StatusPayload`, `@Published var connected: Bool`, `var worstState: AgentState?`, and a `start()` that begins a 1s async poll loop. Polling auto-starts in `init()`.

- [ ] **Step 1: Write the model**

`macapp/Sources/ClaudeWatchBar/StatusModel.swift`:

```swift
import Foundation
import ClaudeWatchKit

@MainActor
final class StatusModel: ObservableObject {
    @Published var payload = StatusPayload(counts: Counts(), agents: [])
    @Published var connected = false

    private let url = URL(string: "http://127.0.0.1:7459/status")!
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init() {
        start()
    }

    func start() {
        Task { @MainActor in
            while !Task.isCancelled {
                await fetch()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func fetch() async {
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 2
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                connected = false
                return
            }
            payload = try decoder.decode(StatusPayload.self, from: data)
            connected = true
        } catch {
            connected = false
        }
    }

    var worstState: AgentState? {
        if payload.counts.needsInput > 0 { return .needsInput }
        if payload.counts.running > 0 { return .running }
        if payload.counts.done > 0 { return .done }
        if payload.counts.idle > 0 { return .idle }
        return nil
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd macapp && swift build`
Expected: builds `ClaudeWatchKit` and starts compiling `ClaudeWatchBar`. It will FAIL only because there is no `@main` yet (`error: 'main' attribute cannot be used...` / missing entry). That is expected and fixed in Task 5. If you see a *type* error referencing `StatusModel`, fix it now; an entry-point/`@main` error is acceptable to carry into Task 5.

- [ ] **Step 3: Commit**

```bash
git add macapp/Sources/ClaudeWatchBar/StatusModel.swift
git commit -m "feat(macapp): StatusModel polling http://127.0.0.1:7459/status"
```

---

### Task 5: Mac app — panel UI + MenuBarExtra entry

**Files:**
- Create: `macapp/Sources/ClaudeWatchBar/Theme.swift`
- Create: `macapp/Sources/ClaudeWatchBar/PanelView.swift`
- Create: `macapp/Sources/ClaudeWatchBar/ClaudeWatchBarApp.swift`

**Interfaces:**
- Consumes: `StatusModel` (Task 4), `Agent`/`AgentState`/`Counts` (`ClaudeWatchKit`).
- Produces: the runnable app — `@main struct ClaudeWatchBarApp: App` with a `MenuBarExtra(.window)` rendering `PanelView`.

- [ ] **Step 1: Theme helpers (color + relative time)**

`macapp/Sources/ClaudeWatchBar/Theme.swift`:

```swift
import SwiftUI
import ClaudeWatchKit

extension AgentState {
    var color: Color {
        switch self {
        case .needsInput: return .orange
        case .running: return .blue
        case .done: return .green
        case .idle: return .secondary
        }
    }
}

func relativeAge(_ seconds: Double) -> String {
    if seconds < 60 { return "\(Int(seconds))s" }
    if seconds < 3600 { return "\(Int(seconds / 60))m" }
    return "\(Int(seconds / 3600))h"
}
```

- [ ] **Step 2: Panel view**

`macapp/Sources/ClaudeWatchBar/PanelView.swift`:

```swift
import SwiftUI
import ClaudeWatchKit

struct PanelView: View {
    @ObservedObject var model: StatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Claude Agents").font(.headline)
                Spacer()
                CountPills(counts: model.payload.counts)
            }
            Divider().opacity(0.4)
            if model.payload.agents.isEmpty {
                Text(model.connected ? "No active agents" : "Waiting for daemon…")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(model.payload.agents.enumerated()), id: \.offset) { _, agent in
                            AgentRow(agent: agent)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
            Divider().opacity(0.4)
            HStack(spacing: 6) {
                Circle()
                    .fill(model.connected ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(model.connected ? "connected" : "daemon offline")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(.ultraThinMaterial)
    }
}

struct AgentRow: View {
    let agent: Agent
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(agent.agentState.color).frame(width: 9, height: 9)
            Text(agent.project)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(hovered ? 0.08 : 0))
        )
        .onHover { hovered = $0 }
    }

    private var detail: String {
        switch agent.agentState {
        case .needsInput: return "needs input"
        case .running: return "running \(relativeAge(agent.ageSeconds))"
        case .done: return "done"
        case .idle: return "idle \(relativeAge(agent.ageSeconds))"
        }
    }
}

struct CountPills: View {
    let counts: Counts

    var body: some View {
        HStack(spacing: 5) {
            pill(counts.needsInput, .orange)
            pill(counts.running, .blue)
            pill(counts.done, .green)
            pill(counts.idle, .secondary)
        }
    }

    @ViewBuilder
    private func pill(_ n: Int, _ c: Color) -> some View {
        if n > 0 {
            HStack(spacing: 3) {
                Circle().fill(c).frame(width: 6, height: 6)
                Text("\(n)").font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(c.opacity(0.15)))
        }
    }
}
```

- [ ] **Step 3: App entry point**

`macapp/Sources/ClaudeWatchBar/ClaudeWatchBarApp.swift`:

```swift
import SwiftUI
import ClaudeWatchKit

@main
struct ClaudeWatchBarApp: App {
    @StateObject private var model = StatusModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            Image(systemName: iconName)
        }
        .menuBarExtraStyle(.window)
    }

    private var iconName: String {
        switch model.worstState {
        case .needsInput: return "bell.badge.fill"
        case .running: return "circle.dotted"
        case .done: return "checkmark.circle.fill"
        case .idle: return "moon.zzz.fill"
        case .none: return "circle.dashed"
        }
    }
}
```

- [ ] **Step 4: Verify the whole package builds**

Run: `cd macapp && swift build -c release`
Expected: builds with no errors, produces `.build/release/ClaudeWatchBar`.

- [ ] **Step 5: Commit**

```bash
git add macapp/Sources/ClaudeWatchBar/Theme.swift macapp/Sources/ClaudeWatchBar/PanelView.swift macapp/Sources/ClaudeWatchBar/ClaudeWatchBarApp.swift
git commit -m "feat(macapp): translucent MenuBarExtra panel + status-driven icon"
```

---

### Task 6: Mac app — `.app` bundle build script

**Files:**
- Create: `macapp/build.sh`

**Interfaces:**
- Consumes: the release binary from `swift build -c release`.
- Produces: `macapp/ClaudeWatchBar.app` (LSUIElement, local-networking ATS, runnable via `open`).

- [ ] **Step 1: Write the build script**

`macapp/build.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP="ClaudeWatchBar"
BUNDLE="${APP}.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/${APP}"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP"

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ClaudeWatchBar</string>
  <key>CFBundleExecutable</key><string>ClaudeWatchBar</string>
  <key>CFBundleIdentifier</key><string>com.claudewatch.menubar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST

echo "Built ${BUNDLE}"
echo "Run: open ${BUNDLE}"
```

- [ ] **Step 2: Make it executable and run it**

Run: `cd macapp && chmod +x build.sh && ./build.sh`
Expected: ends with `Built ClaudeWatchBar.app`; `ls ClaudeWatchBar.app/Contents/MacOS/ClaudeWatchBar` exists.

- [ ] **Step 3: Commit**

```bash
git add macapp/build.sh
git commit -m "feat(macapp): build.sh assembles LSUIElement .app bundle"
```

---

### Task 7: Manual end-to-end verification + README

**Files:**
- Modify: `README.md` (add "Mac menu bar app" section)

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Launch daemon (mock) and app together**

```bash
cd daemon && .venv/bin/python claude_watch_daemon.py --mock --port 7459 &
cd ../macapp && ./build.sh && open ClaudeWatchBar.app
```

- [ ] **Step 2: Inject synthetic events and confirm the panel updates**

```bash
curl -s -X POST http://127.0.0.1:7459/event -d '{"session_id":"a","event":"needs_input","cwd":"/p/compile-me"}'
curl -s -X POST http://127.0.0.1:7459/event -d '{"session_id":"b","event":"running","cwd":"/p/claude-watchh"}'
curl -s http://127.0.0.1:7459/status
```

Expected: `curl …/status` returns JSON with both agents (needs_input first). In the menu bar: the icon shows the attention/bell glyph; clicking opens a translucent panel listing `compile-me` (orange dot, "needs input") and `claude-watchh` (blue dot, "running …"), with count pills in the header. Confirm the panel material/rounding reads like Control Center. Kill the daemon → footer flips to "daemon offline" within ~2s.

- [ ] **Step 3: Clean up processes**

```bash
pkill -f claude_watch_daemon.py || true
osascript -e 'quit app "ClaudeWatchBar"' 2>/dev/null || pkill -f ClaudeWatchBar || true
```

- [ ] **Step 4: Document in README**

Append to `README.md`:

```markdown
## Mac menu bar app

A native menu bar app (`macapp/`) shows every active Claude agent across all
projects, styled like Control Center. It reads the same daemon as the watch.

Build and run:

```bash
cd macapp && ./build.sh && open ClaudeWatchBar.app
```

The daemon serves the app at `GET http://127.0.0.1:7459/status` and runs with or
without the hardware watch (`python claude_watch_daemon.py --mock` is enough for
the menu bar app). The app polls once per second and shows "daemon offline" when
it can't reach the daemon.
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: Mac menu bar app build/run instructions"
```

---

## Self-Review

**Spec coverage:**
- Architecture / data flow (poll `GET /status`) → Tasks 2, 4. ✓
- Daemon `status()` + endpoint + BLE-optional → Tasks 1, 2. ✓
- BLE payload unchanged → Task 1 only adds a method; verified Task 2 Step 6. ✓
- MenuBarExtra window panel, material, rows, pills, icon, empty state, footer/connection, Quit → Task 5. ✓
- Relative timing from `age_seconds` → Tasks 1 (`age_seconds`), 5 (`relativeAge`). ✓
- Resilience (offline handling) → Task 4 (`connected=false` on error), Task 5 (footer + waiting state). ✓
- Build script / LSUIElement / ATS localhost → Task 6. ✓
- Tests: pytest (Tasks 1–2), swift decode test (Task 3). ✓
- README → Task 7. ✓

**Placeholder scan:** none — all steps carry concrete code/commands.

**Type consistency:** `StatusPayload`/`Counts`/`Agent`/`AgentState` names + `.convertFromSnakeCase` decoder are consistent across Tasks 3–5. `status()` JSON keys (`needs_input`,`running`,`done`,`idle`,`project`,`state`,`age_seconds`) match the decoder's expected camelCase mapping. `worstState`/`iconName` switch is exhaustive over `AgentState` + `nil`.
