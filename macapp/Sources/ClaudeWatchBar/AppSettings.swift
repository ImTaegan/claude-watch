import Foundation
import ServiceManagement

/// User preferences, persisted in UserDefaults. Toggling notifications/sound
/// updates the Notifier; toggling launch-at-login registers the app as a login
/// item (best-effort — silently no-ops if the OS refuses, e.g. unsigned build).
@MainActor
final class AppSettings: ObservableObject {
    @Published var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
            Notifier.enabled = notificationsEnabled
        }
    }
    @Published var soundEnabled: Bool {
        didSet {
            defaults.set(soundEnabled, forKey: "soundEnabled")
            Notifier.soundEnabled = soundEnabled
        }
    }
    @Published var usageAlertsEnabled: Bool {
        didSet {
            defaults.set(usageAlertsEnabled, forKey: "usageAlertsEnabled")
            Notifier.usageAlertsEnabled = usageAlertsEnabled
        }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin(launchAtLogin) }
    }

    private let defaults = UserDefaults.standard
    private var applyingLaunch = false

    init() {
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        usageAlertsEnabled = defaults.object(forKey: "usageAlertsEnabled") as? Bool ?? true
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
        // didSet doesn't fire during init, so apply the Notifier flags directly.
        Notifier.enabled = notificationsEnabled
        Notifier.soundEnabled = soundEnabled
        Notifier.usageAlertsEnabled = usageAlertsEnabled
    }

    private func applyLaunchAtLogin(_ on: Bool) {
        guard !applyingLaunch else { return }  // ignore the revert's re-entrant didSet
        applyingLaunch = true
        defer { applyingLaunch = false }
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Reflect what actually happened rather than the requested value.
            // The guard above makes this assignment's didSet a no-op.
            let actual = (SMAppService.mainApp.status == .enabled)
            if actual != launchAtLogin { launchAtLogin = actual }
        }
    }
}
