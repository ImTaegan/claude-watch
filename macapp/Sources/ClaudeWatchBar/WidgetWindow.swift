import AppKit
import SwiftUI

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

    /// Re-open the widget at launch if it was open last time.
    func restoreIfNeeded(model: StatusModel, settings: AppSettings) {
        if settings.widgetOpen { show(model: model, settings: settings) }
    }

    private func show(model: StatusModel, settings: AppSettings) {
        if panel == nil {
            let root = PanelView(model: model, settings: settings)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            let host = NSHostingController(rootView: AnyView(root))
            let p = NSPanel(contentViewController: host)
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
