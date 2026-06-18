import Foundation
import ClaudeWatchKit

@MainActor
final class StatusModel: ObservableObject {
    @Published var payload = StatusPayload(counts: Counts(), agents: [])
    @Published var connected = false

    private var lastStates: [String: AgentState] = [:]
    private var hasBaseline = false
    private var usageFired: Set<String> = []
    private var usageHasBaseline = false

    private let url = URL(string: "http://127.0.0.1:7459/status")!
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init() {
        ActiveWindow.requestPermissionIfNeeded()
        start()
    }

    private var pollTask: Task<Void, Never>?

    func start() {
        guard pollTask == nil else { return }  // idempotent: one loop only
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                await fetch()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func fetch() async {
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 2
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                connected = false
                return
            }
            let decoded = try decoder.decode(StatusPayload.self, from: data)
            fireTransitions(decoded.agents)
            fireUsageAlerts(decoded)
            payload = decoded
            connected = true
        } catch {
            connected = false
        }
    }

    /// Fire a notification when an agent newly enters needs-input or done.
    private func fireTransitions(_ agents: [Agent]) {
        let events = detectTransitions(old: lastStates, new: agents,
                                       hasBaseline: hasBaseline)
        if !events.isEmpty {
            // Skip notifying for the terminal you're actively looking at.
            let front = ActiveWindow.frontmostBundleId()
            let title = ActiveWindow.focusedTitle()
            for e in events {
                if agentIsActivelyViewed(e.agent, frontmostBundleId: front,
                                         focusedTitle: title) { continue }
                switch e {
                case .needsInput(let agent): Notifier.needsInput(agent)
                case .done(let agent): Notifier.done(agent)
                }
            }
        }
        // Merge (don't replace): if an agent momentarily drops out of a poll
        // and returns in the same state, we must not treat it as a new
        // transition and re-notify. Absent agents keep their last-known state.
        for a in agents { lastStates[a.id] = a.agentState }
        hasBaseline = true
    }

    /// Fire notifications when usage crosses thresholds (session 80/95, weekly
    /// 90, per-chat context 90). First poll only establishes a baseline.
    private func fireUsageAlerts(_ p: StatusPayload) {
        let alerts = detectUsageAlerts(
            p, sessionThresholds: [80, 95], weeklyThresholds: [90],
            contextThreshold: 90, fired: &usageFired, hasBaseline: usageHasBaseline)
        for alert in alerts {
            switch alert {
            case .session(let pct): Notifier.sessionUsage(pct: pct)
            case .weekly(let pct): Notifier.weeklyUsage(pct: pct)
            case .context(let project, let pct):
                Notifier.contextHigh(project: project, pct: pct)
            }
        }
        usageHasBaseline = true
    }

    var sessionUsagePct: Int? { payload.limits?.fiveHour?.usedPercentage }

    var worstState: AgentState? {
        if payload.counts.needsInput > 0 { return .needsInput }
        if payload.counts.running > 0 { return .running }
        if payload.counts.done > 0 { return .done }
        if payload.counts.idle > 0 { return .idle }
        return nil
    }
}
