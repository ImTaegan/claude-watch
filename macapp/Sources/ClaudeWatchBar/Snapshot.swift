import SwiftUI
import ClaudeWatchKit

/// Renders the panel offscreen over a desktop-like backdrop so the
/// translucent material is visible. Used for visual verification / README.
@MainActor
enum Snapshot {
    static func write(to path: String) {
        let model = StatusModel()
        model.connected = true
        model.payload = StatusPayload(
            counts: Counts(needsInput: 2, running: 2, done: 1, idle: 1),
            agents: [
                Agent(id: "a", project: "compile-me", state: 3, ageSeconds: 8,
                      tool: "Bash", term: "iTerm.app", tty: "/dev/ttys003",
                      waitingSeconds: 92),
                Agent(id: "f", project: "api-gateway", state: 3, ageSeconds: 410,
                      tool: "Edit", term: "Apple_Terminal", tty: "/dev/ttys006",
                      waitingSeconds: 410),
                Agent(id: "b", project: "claude-watchh", state: 1, ageSeconds: 142,
                      tool: "Edit", term: "vscode"),
                Agent(id: "c", project: "growth-saloon", state: 1, ageSeconds: 17,
                      tool: "Bash", term: "iTerm.app"),
                Agent(id: "d", project: "gs-referral", state: 2, ageSeconds: 4,
                      tool: "Read", term: "Apple_Terminal"),
                Agent(id: "e", project: "watch-firmware", state: 0, ageSeconds: 905,
                      tool: "Grep"),
            ]
        )

        let content = ZStack {
            LinearGradient(
                colors: [.purple, .pink, .orange],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            PanelView(model: model, scrolls: false)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(28)
        }
        .fixedSize()

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let cg = renderer.cgImage else {
            FileHandle.standardError.write(Data("snapshot: render failed\n".utf8))
            exit(1)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("snapshot: png encode failed\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
            exit(1)
        }
    }
}
