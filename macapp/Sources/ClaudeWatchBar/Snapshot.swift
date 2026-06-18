import SwiftUI
import ClaudeWatchKit

/// Renders the panel offscreen over a desktop-like backdrop so the
/// translucent material is visible. Used for visual verification / README.
@MainActor
enum Snapshot {
    static func write(to path: String) {
        let now = Date().timeIntervalSince1970
        let model = StatusModel()
        model.connected = true
        model.payload = StatusPayload(
            counts: Counts(needsInput: 2, running: 2, done: 1, idle: 1),
            agents: [
                Agent(id: "a", project: "compile-me", state: 3, ageSeconds: 8,
                      tool: "Bash", detail: "permission to use Bash",
                      term: "iTerm.app", tty: "/dev/ttys003",
                      waitingSeconds: 92, contextPct: 64),
                Agent(id: "f", project: "api-gateway", state: 3, ageSeconds: 410,
                      tool: "Edit", detail: "Should I switch auth to JWT?",
                      term: "Apple_Terminal", tty: "/dev/ttys006",
                      waitingSeconds: 410, contextPct: 88),
                Agent(id: "b", project: "claude-watchh", state: 1, ageSeconds: 142,
                      tool: "Edit", detail: "StatusModel.swift", term: "vscode",
                      contextPct: 92, contextTrend: "up"),
                Agent(id: "c", project: "growth-saloon", state: 1, ageSeconds: 17,
                      tool: "Bash", detail: "npm run build", term: "iTerm.app",
                      contextPct: 31),
                Agent(id: "d", project: "gs-referral", state: 2, ageSeconds: 4,
                      tool: "Read", term: "Apple_Terminal", contextPct: 47),
                Agent(id: "e", project: "watch-firmware", state: 0, ageSeconds: 905,
                      tool: "Grep", contextPct: 12),
            ],
            limits: Limits(
                fiveHour: LimitWindow(usedPercentage: 72, resetsAt: now + 9600,
                                      etaSeconds: 1500),
                sevenDay: LimitWindow(usedPercentage: 38, resetsAt: now + 6 * 86400)
            ),
            todayOutputTokens: 1_240_000
        )

        let content = ZStack {
            LinearGradient(
                colors: [.purple, .pink, .orange],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            PanelView(model: model, settings: AppSettings(), scrolls: false)
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
