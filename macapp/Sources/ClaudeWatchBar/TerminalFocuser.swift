import Foundation
import ClaudeWatchKit

/// Runs the AppleScript that brings an agent's terminal to the front.
/// Best-effort and non-blocking; failures are swallowed.
enum TerminalFocuser {
    static func focus(_ agent: Agent) {
        guard let script = terminalFocusScript(term: agent.term, tty: agent.tty) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }

    static func canFocus(_ agent: Agent) -> Bool {
        terminalFocusScript(term: agent.term, tty: agent.tty) != nil
    }
}
