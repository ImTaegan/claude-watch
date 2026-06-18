import Foundation

/// Fires native macOS notifications. Uses `osascript display notification`,
/// which works for an unsigned/ad-hoc dev build without the UNUserNotification
/// signing + authorization dance, and plays a system sound.
enum Notifier {
    static var enabled = true
    static var soundEnabled = true
    static var usageAlertsEnabled = true

    static func needsInput(project: String) {
        post(title: "\(project) needs you",
             body: "An agent is waiting for your input.",
             sound: "Submarine")
    }

    static func done(project: String) {
        post(title: "\(project) finished",
             body: "An agent just completed its task.",
             sound: "Glass")
    }

    static func sessionUsage(pct: Int) {
        guard usageAlertsEnabled else { return }
        post(title: "Session usage \(pct)%",
             body: "Approaching your 5-hour limit.", sound: "Funk")
    }

    static func weeklyUsage(pct: Int) {
        guard usageAlertsEnabled else { return }
        post(title: "Weekly usage \(pct)%",
             body: "Approaching your weekly limit.", sound: "Funk")
    }

    static func contextHigh(project: String, pct: Int) {
        guard usageAlertsEnabled else { return }
        post(title: "\(project) context \(pct)%",
             body: "Consider /compact or a fresh session.", sound: "Tink")
    }

    private static func post(title: String, body: String, sound: String) {
        guard enabled else { return }
        let soundClause = soundEnabled ? " sound name \"\(escape(sound))\"" : ""
        let script = "display notification \"\(escape(body))\" "
            + "with title \"\(escape(title))\"" + soundClause
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }

    private static func escape(_ s: String) -> String {
        // AppleScript string literals can't contain raw newlines, and quotes/
        // backslashes must be escaped or the notification silently fails.
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: " ")
         .replacingOccurrences(of: "\r", with: " ")
    }
}
