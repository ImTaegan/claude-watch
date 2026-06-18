import Foundation
import ClaudeWatchKit

@MainActor
final class StatusModel: ObservableObject {
    @Published var payload = StatusPayload(counts: Counts(), agents: [])
    @Published var connected = false

    private let url = URL(string: "http://127.0.0.1:7459/status")!
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init() {
        start()
    }

    func start() {
        Task { @MainActor in
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
            payload = try decoder.decode(StatusPayload.self, from: data)
            connected = true
        } catch {
            connected = false
        }
    }

    var worstState: AgentState? {
        if payload.counts.needsInput > 0 { return .needsInput }
        if payload.counts.running > 0 { return .running }
        if payload.counts.done > 0 { return .done }
        if payload.counts.idle > 0 { return .idle }
        return nil
    }
}
