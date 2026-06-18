import SwiftUI
import ClaudeWatchKit

extension AgentState {
    var color: Color {
        switch self {
        case .needsInput: return .orange
        case .running: return .blue
        case .done: return .green
        case .idle: return .secondary
        }
    }
}

func relativeAge(_ seconds: Double) -> String {
    if seconds < 60 { return "\(Int(seconds))s" }
    if seconds < 3600 { return "\(Int(seconds / 60))m" }
    return "\(Int(seconds / 3600))h"
}
