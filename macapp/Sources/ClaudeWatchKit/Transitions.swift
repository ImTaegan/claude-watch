import Foundation

/// A state change worth notifying the user about.
public enum Transition: Equatable, Sendable {
    case needsInput(project: String)
    case done(project: String)
}

/// Pure transition detector: given the previous state-by-id map and the new
/// agent list, return the notifications to fire. When `hasBaseline` is false
/// (the first poll) nothing fires — we only record the starting point so we
/// don't announce every agent that was already active at launch.
public func detectTransitions(
    old: [String: AgentState],
    new: [Agent],
    hasBaseline: Bool
) -> [Transition] {
    guard hasBaseline else { return [] }
    var out: [Transition] = []
    for a in new {
        let prev = old[a.id]
        if a.agentState == .needsInput, prev != .needsInput {
            out.append(.needsInput(project: a.project))
        } else if a.agentState == .done, prev != .done {
            out.append(.done(project: a.project))
        }
    }
    return out
}

public func stateMap(_ agents: [Agent]) -> [String: AgentState] {
    Dictionary(agents.map { ($0.id, $0.agentState) }, uniquingKeysWith: { _, new in new })
}
