import AppKit
import UserNotifications

/// Sets up notification handling: requests authorization (enabling tappable
/// UNUserNotifications) and, on tap, focuses the agent's terminal from the
/// focus info carried in the notification's userInfo.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Notifier.useUserNotifications = granted
        }
    }

    // Present banners even though we're an accessory (menu bar) app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Tapping a notification focuses that agent's terminal.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let term = info["term"] as? String
        let tty = info["tty"] as? String
        let cwd = info["cwd"] as? String
        if term != nil || tty != nil || cwd != nil {
            TerminalFocuser.focus(term: term, tty: tty, cwd: cwd)
        }
        completionHandler()
    }
}
