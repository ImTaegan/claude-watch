import SwiftUI
import ClaudeWatchKit

struct PanelView: View {
    @ObservedObject var model: StatusModel
    @ObservedObject var settings: AppSettings
    /// Offscreen renderers (ImageRenderer) don't draw ScrollView content;
    /// snapshots set this false to render the rows in a plain stack.
    var scrolls = true
    @State private var showSettings = false

    private var agentList: some View {
        VStack(spacing: 2) {
            ForEach(model.payload.agents) { agent in
                AgentRow(agent: agent)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.25), value: model.payload.agents)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude Agents").font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let limits = model.payload.limits {
                UsageSummaryView(limits: limits, now: Date().timeIntervalSince1970)
            }
            if let today = model.payload.todayOutputTokens, today > 0 {
                HStack {
                    Text("Today").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(compactTokens(today)) tokens out")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Divider().opacity(0.4)
            if model.payload.agents.isEmpty {
                Text(model.connected ? "No active agents" : "Waiting for daemon…")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else if scrolls {
                ScrollView { agentList }
                    .frame(maxHeight: 280)
            } else {
                agentList
            }
            if showSettings {
                SettingsView(settings: settings)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Divider().opacity(0.4)
            HStack(spacing: 10) {
                Circle()
                    .fill(model.connected ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(model.connected ? "connected" : "daemon offline")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    WidgetWindow.shared.toggle(model: model, settings: settings)
                } label: {
                    Image(systemName: "macwindow").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Pop out as a floating desktop widget")
                Button {
                    withAnimation(.snappy(duration: 0.2)) { showSettings.toggle() }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(showSettings ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
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

    private var canFocus: Bool { TerminalFocuser.canFocus(agent) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: agent.activityIcon)
                .font(.system(size: 15))
                .foregroundStyle(agent.displayColor)
                .frame(width: 20)
                .symbolEffect(.variableColor.iterative, options: .repeating,
                              isActive: agent.agentState == .running)
                .symbolEffect(.pulse, options: .repeating,
                              isActive: agent.agentState == .needsInput)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(agent.project)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let pct = agent.contextPct {
                        HStack(spacing: 2) {
                            if agent.contextTrend == "up", pct >= 70 {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(usageTier(pct).color)
                            } else if agent.contextTrend == "down" {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(pct)%")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(usageTier(pct) == .normal ? .secondary : usageTier(pct).color)
                        }
                        .help("context: \(agent.contextTokens ?? 0) of \(agent.contextSize ?? 0) tokens")
                    }
                    if hovered && canFocus {
                        Image(systemName: "arrow.up.forward.app.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(agent.timeText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(hovered && canFocus ? "click to focus terminal" : agent.activityText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(agent.isStuck ? Color.red.opacity(0.12)
                                    : Color.primary.opacity(hovered ? 0.10 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture { TerminalFocuser.focus(agent) }
        .contextMenu {
            if canFocus {
                Button("Focus Terminal") { TerminalFocuser.focus(agent) }
            }
            if let cwd = agent.cwd, !cwd.isEmpty {
                Button("Reveal in Finder") { ProjectActions.revealInFinder(cwd) }
                Button("Copy Path") { ProjectActions.copyPath(cwd) }
            }
        }
        .help(canFocus ? "Click to focus \(agent.project)'s terminal" : agent.project)
        .onHover { inside in
            hovered = inside
            if inside && canFocus { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Notify on needs-input / done", isOn: $settings.notificationsEnabled)
            Toggle("Usage alerts (limits & context)", isOn: $settings.usageAlertsEnabled)
                .disabled(!settings.notificationsEnabled)
            Toggle("Play a sound", isOn: $settings.soundEnabled)
                .disabled(!settings.notificationsEnabled)
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.caption)
        .padding(.vertical, 4)
    }
}

// (Count pills removed — the per-row state and the menu-bar badge cover it.)
