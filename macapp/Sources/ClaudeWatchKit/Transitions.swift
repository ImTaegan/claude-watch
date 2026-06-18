import Foundation

/// A state change worth notifying the user about. Carries the agent so the
/// notification can focus its terminal on tap.
public enum Transition: Equatable, Sendable {
    case needsInput(Agent)
    case done(Agent)
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
            out.append(.needsInput(a))
        } else if a.agentState == .done, prev != .done {
            out.append(.done(a))
        }
    }
    return out
}

public func stateMap(_ agents: [Agent]) -> [String: AgentState] {
    Dictionary(agents.map { ($0.id, $0.agentState) }, uniquingKeysWith: { _, new in new })
}
