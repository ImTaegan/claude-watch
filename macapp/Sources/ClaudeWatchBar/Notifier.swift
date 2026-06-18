import Foundation
import ClaudeWatchKit

/// Fires native macOS notifications. Prefers `terminal-notifier` when present:
/// it's notarized (so notifications reliably show) and supports a click action,
/// which we use to focus the agent's terminal. Falls back to `osascript display
/// notification` (always works, but a click just opens Script Editor).
enum Notifier {
    static var enabled = true
    static var soundEnabled = true
    static var usageAlertsEnabled = true

    /// Resolved path to terminal-notifier, or nil if not installed.
    static let notifierPath: String? = {
        for p in ["/opt/homebrew/bin/terminal-notifier", "/usr/local/bin/terminal-notifier"]
            where FileManager.default.isExecutableFile(atPath: p) { return p }
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["terminal-notifier"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                         encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (out?.isEmpty == false) ? out : nil
    }()

    static func needsInput(_ a: Agent) {
        deliver("\(a.project) needs you",
                a.detail ?? "Waiting for your input.", "Submarine", focus: a)
    }

    static func done(_ a: Agent) {
        deliver("\(a.project) finished", "An agent just completed its task.",
                "Glass", focus: a)
    }

    static func sessionUsage(pct: Int) {
        guard usageAlertsEnabled else { return }
        deliver("Session usage \(pct)%", "Approaching your 5-hour limit.", "Funk", focus: nil)
    }

    static func weeklyUsage(pct: Int) {
        guard usageAlertsEnabled else { return }
        deliver("Weekly usage \(pct)%", "Approaching your weekly limit.", "Funk", focus: nil)
    }

    static func contextHigh(project: String, pct: Int) {
        guard usageAlertsEnabled else { return }
        deliver("\(project) context \(pct)%", "Consider /compact or a fresh session.",
                "Tink", focus: nil)
    }

    private static func deliver(_ title: String, _ body: String, _ sound: String, focus: Agent?) {
        guard enabled else { return }
        if let path = notifierPath {
            postTerminalNotifier(path, title, body, sound, focus)
        } else {
            postViaOsascript(title, body, sound)
        }
    }

    private static func postTerminalNotifier(_ path: String, _ title: String,
                                             _ body: String, _ sound: String, _ focus: Agent?) {
        var args = ["-title", title, "-message", body, "-group", "claude-watch"]
        if soundEnabled { args += ["-sound", sound] }
        if let f = focus, let exe = Bundle.main.executableURL?.path,
           !(f.term == nil && f.tty == nil && f.cwd == nil) {
            args += ["-execute", focusCommand(exe: exe, focus: f)]
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
    }

    /// A shell command (run by terminal-notifier on click) that re-invokes this
    /// app binary in `--focus` mode. Single-quoted args survive spaces in paths.
    private static func focusCommand(exe: String, focus f: Agent) -> String {
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        var cmd = q(exe) + " --focus"
        if let t = f.term { cmd += " --term " + q(t) }
        if let t = f.tty { cmd += " --tty " + q(t) }
        if let c = f.cwd { cmd += " --cwd " + q(c) }
        return cmd
    }

    private static func postViaOsascript(_ title: String, _ body: String, _ sound: String) {
        let soundClause = soundEnabled ? " sound name \"\(escape(sound))\"" : ""
        let script = "display notification \"\(escape(body))\" "
            + "with title \"\(escape(title))\"" + soundClause
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: " ")
         .replacingOccurrences(of: "\r", with: " ")
    }
}
