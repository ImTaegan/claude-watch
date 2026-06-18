import XCTest
@testable import ClaudeWatchKit

final class UsageAlertsTests: XCTestCase {
    private func payload(session: (Int, Double)? = nil,
                         weekly: (Int, Double)? = nil,
                         agents: [Agent] = []) -> StatusPayload {
        StatusPayload(
            counts: Counts(),
            agents: agents,
            limits: Limits(
                fiveHour: session.map { LimitWindow(usedPercentage: $0.0, resetsAt: $0.1) },
                sevenDay: weekly.map { LimitWindow(usedPercentage: $0.0, resetsAt: $0.1) }
            )
        )
    }
    private let S = [80, 95], W = [90], C = 90

    func testFirstPollBaselineDoesNotAlert() {
        var fired = Set<String>()
        let a = detectUsageAlerts(payload(session: (85, 1000)), sessionThresholds: S,
                                  weeklyThresholds: W, contextThreshold: C,
                                  fired: &fired, hasBaseline: false)
        XCTAssertTrue(a.isEmpty)
        XCTAssertTrue(fired.contains("session@1000@80"))
    }

    func testSessionCrossesThresholdOnce() {
        var fired = Set<String>()
        _ = detectUsageAlerts(payload(session: (50, 1000)), sessionThresholds: S,
                              weeklyThresholds: W, contextThreshold: C,
                              fired: &fired, hasBaseline: true)
        let a1 = detectUsageAlerts(payload(session: (82, 1000)), sessionThresholds: S,
                                   weeklyThresholds: W, contextThreshold: C,
                                   fired: &fired, hasBaseline: true)
        XCTAssertEqual(a1, [.session(pct: 80)])
        // staying high does not re-fire
        let a2 = detectUsageAlerts(payload(session: (84, 1000)), sessionThresholds: S,
                                   weeklyThresholds: W, contextThreshold: C,
                                   fired: &fired, hasBaseline: true)
        XCTAssertTrue(a2.isEmpty)
        // crossing the next threshold fires it
        let a3 = detectUsageAlerts(payload(session: (96, 1000)), sessionThresholds: S,
                                   weeklyThresholds: W, contextThreshold: C,
                                   fired: &fired, hasBaseline: true)
        XCTAssertEqual(a3, [.session(pct: 95)])
    }

    func testWindowResetReArms() {
        var fired = Set<String>()
        _ = detectUsageAlerts(payload(session: (82, 1000)), sessionThresholds: S,
                              weeklyThresholds: W, contextThreshold: C,
                              fired: &fired, hasBaseline: true)  // fires 80 for resetsAt=1000
        let a = detectUsageAlerts(payload(session: (82, 2000)), sessionThresholds: S,
                                  weeklyThresholds: W, contextThreshold: C,
                                  fired: &fired, hasBaseline: true)  // new window
        XCTAssertEqual(a, [.session(pct: 80)])
        // the previous window's key was pruned, so the set doesn't accumulate
        XCTAssertFalse(fired.contains("session@1000@80"))
        XCTAssertTrue(fired.contains("session@2000@80"))
    }

    func testContextAlertAndReArm() {
        var fired = Set<String>()
        let hot = Agent(id: "s1", project: "compile-me", state: 1, ageSeconds: 0, contextPct: 92)
        let a1 = detectUsageAlerts(payload(agents: [hot]), sessionThresholds: S,
                                   weeklyThresholds: W, contextThreshold: C,
                                   fired: &fired, hasBaseline: true)
        XCTAssertEqual(a1, [.context(project: "compile-me", pct: 92)])
        // drops after /compact, then climbs again -> re-arms and fires once more
        let cool = Agent(id: "s1", project: "compile-me", state: 1, ageSeconds: 0, contextPct: 20)
        _ = detectUsageAlerts(payload(agents: [cool]), sessionThresholds: S,
                              weeklyThresholds: W, contextThreshold: C,
                              fired: &fired, hasBaseline: true)
        let a2 = detectUsageAlerts(payload(agents: [hot]), sessionThresholds: S,
                                   weeklyThresholds: W, contextThreshold: C,
                                   fired: &fired, hasBaseline: true)
        XCTAssertEqual(a2, [.context(project: "compile-me", pct: 92)])
    }
}
