import AppKit
import SwiftUI

/// A borderless NSPanel returns false for canBecomeKey by default, which stops
/// the embedded SwiftUI controls (toggles, buttons) from working. Allow it.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// A floating, always-on-top desktop widget that shows the same live PanelView.
/// Borderless + non-activating so it behaves like a HUD you park anywhere;
/// draggable by its background; remembers its position.
@MainActor
final class WidgetWindow {
    static let shared = WidgetWindow()
    private var panel: NSPanel?

    func toggle(model: StatusModel, settings: AppSettings) {
        if let p = panel, p.isVisible {
            p.orderOut(nil)
            settings.widgetOpen = false
        } else {
            show(model: model, settings: settings)
            settings.widgetOpen = true
        }
    }

    /// Re-open the widget at launch if it was open last time. Guarded so it
    /// only acts once (the menu-bar label's .task can re-run on icon changes,
    /// and we must not keep re-raising the panel after the user moves it).
    func restoreIfNeeded(model: StatusModel, settings: AppSettings) {
        guard panel == nil, settings.widgetOpen else { return }
        show(model: model, settings: settings)
    }

    private func show(model: StatusModel, settings: AppSettings) {
        if panel == nil {
            let root = PanelView(model: model, settings: settings)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            let host = NSHostingController(rootView: AnyView(root))
            let p = KeyablePanel(contentViewController: host)
            p.styleMask = [.borderless, .nonactivatingPanel]
            p.isFloatingPanel = true
            p.level = .floating
            p.becomesKeyOnlyIfNeeded = true
            p.isMovableByWindowBackground = true
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.setContentSize(host.view.fittingSize)
            // Default to the top-right corner; autosave remembers moves after.
            if let vf = NSScreen.main?.visibleFrame {
                p.setFrameOrigin(NSPoint(x: vf.maxX - p.frame.width - 20,
                                         y: vf.maxY - p.frame.height - 20))
            }
            p.setFrameAutosaveName("ClaudeWatchWidget")
            panel = p
        }
        panel?.makeKeyAndOrderFront(nil)
    }
}
