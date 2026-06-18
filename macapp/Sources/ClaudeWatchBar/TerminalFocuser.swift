import Foundation
import ClaudeWatchKit

/// Brings an agent's editor/terminal to the front.
/// Best-effort and non-blocking; failures are swallowed.
enum TerminalFocuser {
    static func focus(_ agent: Agent) {
        focus(term: agent.term, tty: agent.tty, cwd: agent.cwd)
    }

    static func focus(term: String?, tty: String?, cwd: String?) {
        run(focusAction(term: term, tty: tty, cwd: cwd), wait: false)
    }

    /// Blocking variant for the `--focus` CLI invocation (used by notification
    /// clicks via terminal-notifier), so the process doesn't exit mid-launch.
    static func focusAndWait(term: String?, tty: String?, cwd: String?) {
        run(focusAction(term: term, tty: tty, cwd: cwd), wait: true)
    }

    private static func run(_ action: FocusAction, wait: Bool) {
        let proc: (String, [String])?
        switch action {
        case .appleScript(let script): proc = ("/usr/bin/osascript", ["-e", script])
        case .openApp(let bundleId, let path):
            proc = ("/usr/bin/open", path.map { ["-b", bundleId, $0] } ?? ["-b", bundleId])
        case .none: proc = nil
        }
        guard let (launch, args) = proc else { return }
        run(launch, args, wait: wait)
    }

    static func canFocus(_ agent: Agent) -> Bool {
        focusAction(term: agent.term, tty: agent.tty, cwd: agent.cwd) != .none
    }

    private static func run(_ launchPath: String, _ args: [String], wait: Bool) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        try? p.run()
        if wait { p.waitUntilExit() }
    }
}
