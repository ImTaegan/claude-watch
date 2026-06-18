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

extension UsageTier {
    /// Text/number tint. Normal stays neutral so only warning/critical pop.
    var color: Color {
        switch self {
        case .normal: return .secondary
        case .warning: return .orange
        case .critical: return .red
        }
    }
    /// Progress-bar fill — visible even when normal.
    var barColor: Color {
        switch self {
        case .normal: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

func relativeAge(_ seconds: Double) -> String {
    if seconds < 60 { return "\(Int(seconds))s" }
    if seconds < 3600 { return "\(Int(seconds / 60))m" }
    return "\(Int(seconds / 3600))h"
}

extension Agent {
    /// SF Symbol shown at the start of a row. For running agents it reflects
    /// the actual tool in use, so you can see what the agent is doing.
    var activityIcon: String {
        switch agentState {
        case .needsInput: return "exclamationmark.bubble.fill"
        case .done: return "checkmark.circle.fill"
        case .idle: return "moon.zzz.fill"
        case .running:
            switch tool {
            case "Bash": return "terminal.fill"
            case "Edit", "Write", "MultiEdit", "NotebookEdit": return "pencil"
            case "Read", "NotebookRead": return "doc.text.fill"
            case "Grep", "Glob", "LS": return "magnifyingglass"
            case "WebFetch", "WebSearch": return "globe"
            case "Task": return "person.2.fill"
            case "TodoWrite": return "checklist"
            default: return "gearshape.fill"
            }
        }
    }

    /// Human-readable description of what the agent is doing right now.
    /// Prefers the concrete `detail` (the file/command/question) when present.
    var activityText: String {
        switch agentState {
        case .needsInput:
            if let d = detail, !d.isEmpty { return d }      // the actual ask
            return isStuck ? "still waiting on you" : "needs your input"
        case .done: return "finished — ready for you"
        case .idle: return "idle"
        case .running:
            if let d = detail, !d.isEmpty {
                switch tool {
                case "Bash": return "$ \(d)"
                case "Edit", "Write", "MultiEdit", "NotebookEdit": return "editing \(d)"
                case "Read", "NotebookRead": return "reading \(d)"
                case "Grep", "Glob": return "searching \(d)"
                case "Task": return "subagent: \(d)"
                default: return d
                }
            }
            switch tool {
            case "Bash": return "running a command"
            case "Edit", "Write", "MultiEdit", "NotebookEdit": return "editing code"
            case "Read", "NotebookRead": return "reading files"
            case "Grep", "Glob", "LS": return "searching the codebase"
            case "WebFetch", "WebSearch": return "browsing the web"
            case "Task": return "running a subagent"
            case "TodoWrite": return "planning"
            case .some(let t): return "using \(t)"
            case .none: return "working…"
            }
        }
    }

    /// Number shown at the trailing edge: time waiting if blocked on you,
    /// otherwise time since last activity.
    var timeText: String {
        if agentState == .needsInput, let w = waitingSeconds {
            return relativeAge(w)
        }
        return relativeAge(ageSeconds)
    }

    /// An agent that's been waiting on you for 5+ minutes — easy to forget.
    var isStuck: Bool {
        agentState == .needsInput && (waitingSeconds ?? 0) >= 300
    }

    /// Row tint: stuck agents go red to pull your eye.
    var displayColor: Color {
        isStuck ? .red : agentState.color
    }
}
