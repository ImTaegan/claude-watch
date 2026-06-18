import Foundation

/// Builds an AppleScript that brings the terminal running a given agent to the
/// front. For iTerm and Terminal we match the exact tab/session by tty; for
/// VS Code (no AppleScript access to integrated terminals) we just activate the
/// editor. Every branch is guarded by `is running` so we never launch a
/// terminal the user doesn't actually use. Returns nil when nothing can be done.
/// A real tty device is "/dev/tty…" with only alphanumerics after. Anything
/// else can't be a tty we'd match on, and refusing it keeps unexpected input
/// from being interpolated into the AppleScript literal.
func isSafeTTY(_ tty: String) -> Bool {
    guard tty.hasPrefix("/dev/"), tty.count <= 64 else { return false }
    let rest = tty.dropFirst("/dev/".count)
    return !rest.isEmpty && rest.allSatisfy { $0.isLetter || $0.isNumber }
}

public func terminalFocusScript(term: String?, tty rawTTY: String?) -> String? {
    if term == "vscode" {
        return guarded(bundleId: "com.microsoft.VSCode", "activate")
    }

    let tty = rawTTY.flatMap { isSafeTTY($0) ? $0 : nil }
    guard let tty, !tty.isEmpty else {
        switch term {
        case "iTerm.app": return guarded(app: "iTerm", "activate")
        case "Apple_Terminal": return guarded(app: "Terminal", "activate")
        default: return nil
        }
    }

    switch term {
    case "Apple_Terminal": return terminalAppScript(tty: tty)
    case "iTerm.app": return itermScript(tty: tty)
    default:
        // Unknown terminal but we have a tty — try both, harmlessly.
        return itermScript(tty: tty) + "\n" + terminalAppScript(tty: tty)
    }
}

private func guarded(app: String, _ body: String) -> String {
    "if application \"\(app)\" is running then tell application \"\(app)\" to \(body)"
}

private func guarded(bundleId: String, _ body: String) -> String {
    "if application id \"\(bundleId)\" is running then "
        + "tell application id \"\(bundleId)\" to \(body)"
}

private func itermScript(tty: String) -> String {
    """
    if application "iTerm" is running then
      tell application "iTerm"
        repeat with w in windows
          repeat with t in tabs of w
            repeat with s in sessions of t
              if (tty of s) is "\(tty)" then
                select w
                tell t to select
                tell s to select
                activate
                return
              end if
            end repeat
          end repeat
        end repeat
      end tell
    end if
    """
}

private func terminalAppScript(tty: String) -> String {
    """
    if application "Terminal" is running then
      tell application "Terminal"
        repeat with w in windows
          repeat with t in tabs of w
            if (tty of t) is "\(tty)" then
              set selected tab of w to t
              set frontmost of w to true
              set index of w to 1
              activate
              return
            end if
          end repeat
        end repeat
      end tell
    end if
    """
}
