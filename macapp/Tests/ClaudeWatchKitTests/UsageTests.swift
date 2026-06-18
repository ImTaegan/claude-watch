import XCTest
@testable import ClaudeWatchKit

final class UsageTests: XCTestCase {
    func testTierThresholds() {
        XCTAssertEqual(usageTier(0), .normal)
        XCTAssertEqual(usageTier(69), .normal)
        XCTAssertEqual(usageTier(70), .warning)
        XCTAssertEqual(usageTier(89), .warning)
        XCTAssertEqual(usageTier(90), .critical)
        XCTAssertEqual(usageTier(100), .critical)
    }

    func testResetCountdown() {
        XCTAssertEqual(resetCountdown(resetsAt: 9600, now: 0), "resets in 2h 40m")
        XCTAssertEqual(resetCountdown(resetsAt: 3600, now: 0), "resets in 1h")
        XCTAssertEqual(resetCountdown(resetsAt: 1800, now: 0), "resets in 30m")
        XCTAssertEqual(resetCountdown(resetsAt: 518400, now: 0), "resets in 6d")
        XCTAssertEqual(resetCountdown(resetsAt: 30, now: 0), "resets now")
        XCTAssertEqual(resetCountdown(resetsAt: 0, now: 100), "resets now")
    }

    func testEtaToLimit() {
        XCTAssertEqual(etaToLimit(1200), "~20m to limit")
        XCTAssertEqual(etaToLimit(4200), "~1h 10m to limit")
        XCTAssertEqual(etaToLimit(3600), "~1h to limit")
        XCTAssertEqual(etaToLimit(20), "~1m to limit")
    }

    func testDecodeStatusWithLimitsAndContext() throws {
        let json = """
        {"counts":{"needs_input":0,"running":1,"done":0,"idle":0},
         "limits":{"five_hour":{"used_percentage":40,"resets_at":1781798400},
                   "seven_day":{"used_percentage":5,"resets_at":1782378000}},
         "agents":[{"id":"s1","project":"p","state":1,"age_seconds":2,
                    "context_pct":35,"context_tokens":351590,"context_size":1000000}]}
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let p = try dec.decode(StatusPayload.self, from: json)
        XCTAssertEqual(p.limits?.fiveHour?.usedPercentage, 40)
        XCTAssertEqual(p.limits?.fiveHour?.resetsAt, 1781798400)
        XCTAssertEqual(p.limits?.sevenDay?.usedPercentage, 5)
        XCTAssertEqual(p.agents[0].contextPct, 35)
        XCTAssertEqual(p.agents[0].contextTokens, 351590)
    }
}
