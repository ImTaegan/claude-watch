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
    public let cwd: String?
    public let waitingSeconds: Double?
    public let contextPct: Int?
    public let contextTokens: Int?
    public let contextSize: Int?
    public let contextTrend: String?

    public init(id: String = "", project: String, state: Int, ageSeconds: Double,
                tool: String? = nil, term: String? = nil, tty: String? = nil,
                cwd: String? = nil, waitingSeconds: Double? = nil,
                contextPct: Int? = nil, contextTokens: Int? = nil,
                contextSize: Int? = nil, contextTrend: String? = nil) {
        self.id = id
        self.project = project
        self.state = state
        self.ageSeconds = ageSeconds
        self.tool = tool
        self.term = term
        self.tty = tty
        self.cwd = cwd
        self.waitingSeconds = waitingSeconds
        self.contextPct = contextPct
        self.contextTokens = contextTokens
        self.contextSize = contextSize
        self.contextTrend = contextTrend
    }

    public var agentState: AgentState { AgentState(rawValue: state) ?? .idle }
}

public struct LimitWindow: Codable, Equatable, Sendable {
    public let usedPercentage: Int
    public let resetsAt: Double
    public let etaSeconds: Double?

    public init(usedPercentage: Int, resetsAt: Double, etaSeconds: Double? = nil) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
        self.etaSeconds = etaSeconds
    }
}

public struct Limits: Codable, Equatable, Sendable {
    public let fiveHour: LimitWindow?
    public let sevenDay: LimitWindow?

    public init(fiveHour: LimitWindow?, sevenDay: LimitWindow?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }
}

public struct StatusPayload: Codable, Equatable, Sendable {
    public let counts: Counts
    public let agents: [Agent]
    public let limits: Limits?
    public let todayOutputTokens: Int?

    public init(counts: Counts, agents: [Agent], limits: Limits? = nil,
                todayOutputTokens: Int? = nil) {
        self.counts = counts
        self.agents = agents
        self.limits = limits
        self.todayOutputTokens = todayOutputTokens
    }
}
