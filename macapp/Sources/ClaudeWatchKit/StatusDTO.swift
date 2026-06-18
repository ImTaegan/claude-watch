import Foundation

public enum AgentState: Int, Codable, Sendable {
    case idle = 0, running = 1, done = 2, needsInput = 3

    public var label: String {
        switch self {
        case .needsInput: return "needs input"
        case .running: return "running"
        case .done: return "done"
        case .idle: return "idle"
        }
    }
}

public struct Counts: Codable, Equatable, Sendable {
    public var needsInput: Int
    public var running: Int
    public var done: Int
    public var idle: Int

    public init(needsInput: Int = 0, running: Int = 0, done: Int = 0, idle: Int = 0) {
        self.needsInput = needsInput
        self.running = running
        self.done = done
        self.idle = idle
    }
}

public struct Agent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let project: String
    public let state: Int
    public let ageSeconds: Double
    public let tool: String?
    public let term: String?
    public let tty: String?
    public let waitingSeconds: Double?

    public init(id: String = "", project: String, state: Int, ageSeconds: Double,
                tool: String? = nil, term: String? = nil, tty: String? = nil,
                waitingSeconds: Double? = nil) {
        self.id = id
        self.project = project
        self.state = state
        self.ageSeconds = ageSeconds
        self.tool = tool
        self.term = term
        self.tty = tty
        self.waitingSeconds = waitingSeconds
    }

    public var agentState: AgentState { AgentState(rawValue: state) ?? .idle }
}

public struct StatusPayload: Codable, Equatable, Sendable {
    public let counts: Counts
    public let agents: [Agent]

    public init(counts: Counts, agents: [Agent]) {
        self.counts = counts
        self.agents = agents
    }
}
