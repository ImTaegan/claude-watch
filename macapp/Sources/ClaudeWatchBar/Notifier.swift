import Foundation
import UserNotifications
import ClaudeWatchKit

/// Fires native macOS notifications. Prefers UNUserNotificationCenter (so a tap
/// can focus the agent's terminal); falls back to `osascript display
/// notification` when notifications aren't authorized (e.g. an unsigned build),
/// which always works but isn't tappable.
enum Notifier {
    static var enabled = true
    static var soundEnabled = true
    static var usageAlertsEnabled = true
    static var useUserNotifications = false  // set true once UN authorization granted

    static func needsInput(_ a: Agent) {
        deliver("\(a.project) needs you", "Waiting for your input.", "Submarine", focus: a)
    }

    static func done(_ a: Agent) {
        deliver("\(a.project) finished", "An agent just completed its task.", "Glass", focus: a)
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
        if useUserNotifications {
            postUserNotification(title, body, focus)
        } else {
            postViaOsascript(title, body, sound)
        }
    }

    private static func postUserNotification(_ title: String, _ body: String, _ focus: Agent?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if soundEnabled { content.sound = .default }
        if let f = focus {
            var info: [String: String] = [:]
            if let t = f.term { info["term"] = t }
            if let t = f.tty { info["tty"] = t }
            if let c = f.cwd { info["cwd"] = c }
            content.userInfo = info
        }
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
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
