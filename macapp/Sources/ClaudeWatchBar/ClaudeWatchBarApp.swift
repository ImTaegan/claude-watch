import SwiftUI
import ClaudeWatchKit

struct ClaudeWatchBarApp: App {
    @StateObject private var model = StatusModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            if model.payload.counts.needsInput > 0 {
                // Show the count right in the menu bar so you don't have to open it.
                Label("\(model.payload.counts.needsInput)", systemImage: "bell.badge.fill")
            } else {
                Image(systemName: iconName)
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var iconName: String {
        switch model.worstState {
        case .needsInput: return "bell.badge.fill"
        case .running: return "circle.dotted"
        case .done: return "checkmark.circle.fill"
        case .idle: return "moon.zzz.fill"
        case .none: return "circle.dashed"
        }
    }
}
