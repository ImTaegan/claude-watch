import Foundation
import ClaudeWatchKit

@MainActor
final class StatusModel: ObservableObject {
    @Published var payload = StatusPayload(counts: Counts(), agents: [])
    @Published var connected = false

    private var lastStates: [String: AgentState] = [:]
    private var hasBaseline = false

    private let url = URL(string: "http://127.0.0.1:7459/status")!
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init() {
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
        for e in events {
            switch e {
            case .needsInput(let project): Notifier.needsInput(project: project)
            case .done(let project): Notifier.done(project: project)
            }
        }
        // Merge (don't replace): if an agent momentarily drops out of a poll
        // and returns in the same state, we must not treat it as a new
        // transition and re-notify. Absent agents keep their last-known state.
        for a in agents { lastStates[a.id] = a.agentState }
        hasBaseline = true
    }

    var worstState: AgentState? {
        if payload.counts.needsInput > 0 { return .needsInput }
        if payload.counts.running > 0 { return .running }
        if payload.counts.done > 0 { return .done }
        if payload.counts.idle > 0 { return .idle }
        return nil
    }
}
