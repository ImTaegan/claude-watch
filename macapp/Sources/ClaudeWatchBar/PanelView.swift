import SwiftUI
import ClaudeWatchKit

struct PanelView: View {
    @ObservedObject var model: StatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Claude Agents").font(.headline)
                Spacer()
                CountPills(counts: model.payload.counts)
            }
            Divider().opacity(0.4)
            if model.payload.agents.isEmpty {
                Text(model.connected ? "No active agents" : "Waiting for daemon…")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(model.payload.agents.enumerated()), id: \.offset) { _, agent in
                            AgentRow(agent: agent)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
            Divider().opacity(0.4)
            HStack(spacing: 6) {
                Circle()
                    .fill(model.connected ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(model.connected ? "connected" : "daemon offline")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(.ultraThinMaterial)
    }
}

struct AgentRow: View {
    let agent: Agent
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(agent.agentState.color).frame(width: 9, height: 9)
            Text(agent.project)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(hovered ? 0.08 : 0))
        )
        .onHover { hovered = $0 }
    }

    private var detail: String {
        switch agent.agentState {
        case .needsInput: return "needs input"
        case .running: return "running \(relativeAge(agent.ageSeconds))"
        case .done: return "done"
        case .idle: return "idle \(relativeAge(agent.ageSeconds))"
        }
    }
}

struct CountPills: View {
    let counts: Counts

    var body: some View {
        HStack(spacing: 5) {
            pill(counts.needsInput, .orange)
            pill(counts.running, .blue)
            pill(counts.done, .green)
            pill(counts.idle, .secondary)
        }
    }

    @ViewBuilder
    private func pill(_ n: Int, _ c: Color) -> some View {
        if n > 0 {
            HStack(spacing: 3) {
                Circle().fill(c).frame(width: 6, height: 6)
                Text("\(n)").font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(c.opacity(0.15)))
        }
    }
}
