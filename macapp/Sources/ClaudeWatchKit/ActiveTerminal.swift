import Foundation

/// Bundle id of the app that hosts a given terminal type.
public func terminalBundleId(for term: String?) -> String? {
    switch term {
    case "vscode": return "com.microsoft.VSCode"
    case "iTerm.app": return "com.googlecode.iterm2"
    case "Apple_Terminal": return "com.apple.Terminal"
    default: return nil
    }
}

/// True when the agent's terminal is the one you're actively looking at: the
/// frontmost app is that terminal AND its focused window references the agent's
/// project. In that case we skip the notification — you already see it.
/// Fails safe: with no focused-window title (e.g. no Accessibility permission)
/// it returns false, so notifications still fire.
public func agentIsActivelyViewed(
    _ agent: Agent,
    frontmostBundleId: String?,
    focusedTitle: String?
) -> Bool {
    guard let expected = terminalBundleId(for: agent.term),
          frontmostBundleId == expected,
          let title = focusedTitle, !title.isEmpty else { return false }
    return title.localizedCaseInsensitiveContains(agent.project)
}
