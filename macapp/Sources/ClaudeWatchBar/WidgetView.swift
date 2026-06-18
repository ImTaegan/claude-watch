import SwiftUI
import ClaudeWatchKit

/// Condensed view for the floating desktop widget: no title, compact usage
/// rings, one-line agent rows. Translucent at rest, solid when hovered.
struct WidgetView: View {
    @ObservedObject var model: StatusModel
    var onClose: () -> Void = {}
    var scrolls = true  // snapshots render rows without a ScrollView
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                if let limits = model.payload.limits {
                    if let s = limits.fiveHour { UsageRing(letter: "S", name: "Session", window: s) }
                    if let w = limits.sevenDay { UsageRing(letter: "W", name: "Week", window: w) }
                }
                Spacer(minLength: 0)
                if hovered {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Close widget")
                }
            }

            if model.payload.agents.isEmpty {
                Text(model.connected ? "no active agents" : "daemon offline")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            } else if scrolls {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(model.payload.agents) { CompactAgentRow(agent: $0) }
                    }
                }
                .frame(maxHeight: 220)
                .scrollIndicators(.never)
            } else {
                VStack(spacing: 1) {
                    ForEach(model.payload.agents) { CompactAgentRow(agent: $0) }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 176, alignment: .leading)
        .background(.ultraThinMaterial)
        .opacity(hovered ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.15), value: hovered)
        .onHover { hovered = $0 }
    }
}

/// A small white ring that fills to a chat's context %; number shows on hover.
struct ContextRing: View {
    let pct: Int
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.18), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: CGFloat(pct) / 100)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 9, height: 9)
        .help("context \(pct)%")
    }
}

/// A small circular progress gauge; the percentage shows on hover.
struct UsageRing: View {
    let letter: String
    let name: String
    let window: LimitWindow

    var body: some View {
        let tier = usageTier(window.usedPercentage)
        ZStack {
            Circle().stroke(Color.primary.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(window.usedPercentage) / 100)
                .stroke(tier.barColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(letter).font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
        }
        .frame(width: 18, height: 18)
        .help("\(name): \(window.usedPercentage)% · "
              + resetCountdown(resetsAt: window.resetsAt, now: Date().timeIntervalSince1970))
    }
}

/// One-line agent row: status icon + project + context %. Hover shows what it's
/// doing; click focuses its terminal.
struct CompactAgentRow: View {
    let agent: Agent
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: agent.activityIcon)
                .font(.system(size: 11))
                .foregroundStyle(agent.displayColor)
                .frame(width: 14)
            Text(agent.project)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let pct = agent.contextPct {
                ContextRing(pct: pct)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 5)
            .fill(Color.primary.opacity(hovered ? 0.10 : 0)))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { TerminalFocuser.focus(agent) }
        .help(agent.activityText)
    }
}
