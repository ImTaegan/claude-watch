import XCTest
@testable import ClaudeWatchKit

final class StatusDTOTests: XCTestCase {
    func testDecodeStatusPayload() throws {
        let json = """
        {"counts":{"needs_input":1,"running":2,"done":0,"idle":1},
         "agents":[{"id":"s2","project":"compile-me","state":3,"age_seconds":4.2,
                    "tool":"Bash","term":"iTerm.app","tty":"/dev/ttys003","waiting_seconds":42.0},
                   {"id":"s1","project":"claude-watchh","state":1,"age_seconds":12.0,
                    "tool":"Edit","term":"vscode","tty":null,"waiting_seconds":null}]}
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let p = try dec.decode(StatusPayload.self, from: json)
        XCTAssertEqual(p.counts, Counts(needsInput: 1, running: 2, done: 0, idle: 1))
        XCTAssertEqual(p.agents.count, 2)
        XCTAssertEqual(p.agents[0].id, "s2")
        XCTAssertEqual(p.agents[0].project, "compile-me")
        XCTAssertEqual(p.agents[0].agentState, .needsInput)
        XCTAssertEqual(p.agents[0].ageSeconds, 4.2, accuracy: 0.001)
        XCTAssertEqual(p.agents[0].tool, "Bash")
        XCTAssertEqual(p.agents[0].term, "iTerm.app")
        XCTAssertEqual(p.agents[0].tty, "/dev/ttys003")
        XCTAssertEqual(p.agents[0].waitingSeconds, 42.0)
        XCTAssertEqual(p.agents[1].agentState, .running)
        XCTAssertNil(p.agents[1].tty)
        XCTAssertNil(p.agents[1].waitingSeconds)
    }

    func testUnknownStateFallsBackToIdle() {
        XCTAssertEqual(Agent(project: "x", state: 99, ageSeconds: 0).agentState, .idle)
    }
}
