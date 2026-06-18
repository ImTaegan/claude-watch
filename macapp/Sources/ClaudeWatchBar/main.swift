import Foundation

// `--snapshot <path>` renders the panel offscreen to a PNG (dev/README aid),
// otherwise launch the menu bar app normally.
func argValue(_ name: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: name),
          i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let path = i + 1 < CommandLine.arguments.count
        ? CommandLine.arguments[i + 1]
        : "panel.png"
    MainActor.assumeIsolated { Snapshot.write(to: path) }
} else if CommandLine.arguments.contains("--focus") {
    // Invoked by a notification click (via terminal-notifier -execute).
    TerminalFocuser.focusAndWait(term: argValue("--term"),
                                 tty: argValue("--tty"),
                                 cwd: argValue("--cwd"))
} else {
    ClaudeWatchBarApp.main()
}
