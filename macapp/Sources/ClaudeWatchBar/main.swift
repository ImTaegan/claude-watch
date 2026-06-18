import Foundation

// `--snapshot <path>` renders the panel offscreen to a PNG (dev/README aid),
// otherwise launch the menu bar app normally.
if let i = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let path = i + 1 < CommandLine.arguments.count
        ? CommandLine.arguments[i + 1]
        : "panel.png"
    MainActor.assumeIsolated { Snapshot.write(to: path) }
} else {
    ClaudeWatchBarApp.main()
}
