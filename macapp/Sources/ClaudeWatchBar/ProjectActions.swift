import AppKit

/// Finder/clipboard actions for an agent's project directory.
enum ProjectActions {
    static func revealInFinder(_ cwd: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
    }

    static func copyPath(_ cwd: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cwd, forType: .string)
    }
}
