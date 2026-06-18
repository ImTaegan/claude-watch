import Foundation

/// Fires native macOS notifications. Uses `osascript display notification`,
/// which works for an unsigned/ad-hoc dev build without the UNUserNotification
/// signing + authorization dance, and plays a system sound.
enum Notifier {
    static var enabled = true
    static var soundEnabled = true

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
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
