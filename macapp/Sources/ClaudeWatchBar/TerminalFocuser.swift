import Foundation
import ClaudeWatchKit

/// Brings an agent's editor/terminal to the front.
/// Best-effort and non-blocking; failures are swallowed.
enum TerminalFocuser {
    static func focus(_ agent: Agent) {
        switch focusAction(term: agent.term, tty: agent.tty, cwd: agent.cwd) {
        case .appleScript(let script):
            run("/usr/bin/osascript", ["-e", script])
        case .openApp(let bundleId, let path):
            run("/usr/bin/open", path.map { ["-b", bundleId, $0] } ?? ["-b", bundleId])
        case .none:
            break
        }
    }

    static func canFocus(_ agent: Agent) -> Bool {
        focusAction(term: agent.term, tty: agent.tty, cwd: agent.cwd) != .none
    }

    private static func run(_ launchPath: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        try? p.run()
    }
}
