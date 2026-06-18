import XCTest
@testable import ClaudeWatchKit

final class StatusDTOTests: XCTestCase {
    func testDecodeStatusPayload() throws {
        let json = """
        {"counts":{"needs_input":1,"running":2,"done":0,"idle":1},
         "agents":[{"project":"compile-me","state":3,"age_seconds":4.2},
                   {"project":"claude-watchh","state":1,"age_seconds":12.0}]}
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let p = try dec.decode(StatusPayload.self, from: json)
        XCTAssertEqual(p.counts, Counts(needsInput: 1, running: 2, done: 0, idle: 1))
        XCTAssertEqual(p.agents.count, 2)
        XCTAssertEqual(p.agents[0].project, "compile-me")
        XCTAssertEqual(p.agents[0].agentState, .needsInput)
        XCTAssertEqual(p.agents[0].ageSeconds, 4.2, accuracy: 0.001)
        XCTAssertEqual(p.agents[1].agentState, .running)
    }

    func testUnknownStateFallsBackToIdle() {
        XCTAssertEqual(Agent(project: "x", state: 99, ageSeconds: 0).agentState, .idle)
    }
}
