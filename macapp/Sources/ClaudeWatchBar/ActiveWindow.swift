import AppKit
import ApplicationServices

/// Inspects the frontmost app + its focused window so we can tell whether you're
/// actively looking at a given agent's terminal. Reading the window title needs
/// Accessibility permission; without it, focusedTitle() returns nil and
/// notification suppression simply doesn't kick in (fails safe).
enum ActiveWindow {
    static func frontmostBundleId() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    static func focusedTitle() -> String? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var window: AnyObject?
        guard AXUIElementCopyAttributeValue(
                axApp, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let win = window else { return nil }
        var title: AnyObject?
        guard AXUIElementCopyAttributeValue(
                win as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success
        else { return nil }
        return title as? String
    }

    /// Prompt once for Accessibility permission (enables active-terminal
    /// notification suppression). No-op if already trusted.
    static func requestPermissionIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
