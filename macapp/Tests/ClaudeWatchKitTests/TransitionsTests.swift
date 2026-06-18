import XCTest
@testable import ClaudeWatchKit

final class TransitionsTests: XCTestCase {
    private func agent(_ id: String, _ state: Int, _ project: String = "p") -> Agent {
        Agent(id: id, project: project, state: state, ageSeconds: 0)
    }

    func testFirstPollEstablishesBaselineWithNoNotifications() {
        let new = [agent("a", 3), agent("b", 2)]  // needs_input, done
        let t = detectTransitions(old: [:], new: new, hasBaseline: false)
        XCTAssertTrue(t.isEmpty)
    }

    func testRunningToNeedsInputNotifies() {
        let old: [String: AgentState] = ["a": .running]
        let new = [agent("a", 3, "compile-me")]
        let t = detectTransitions(old: old, new: new, hasBaseline: true)
        XCTAssertEqual(t, [.needsInput(project: "compile-me")])
    }

    func testRunningToDoneNotifies() {
        let old: [String: AgentState] = ["a": .running]
        let new = [agent("a", 2, "gs-referral")]
        let t = detectTransitions(old: old, new: new, hasBaseline: true)
        XCTAssertEqual(t, [.done(project: "gs-referral")])
    }

    func testStayingInNeedsInputDoesNotRenotify() {
        let old: [String: AgentState] = ["a": .needsInput]
        let new = [agent("a", 3)]
        XCTAssertTrue(detectTransitions(old: old, new: new, hasBaseline: true).isEmpty)
    }

    func testNewAgentAppearingNeedingInputNotifies() {
        // Agent "z" wasn't in the previous map (appeared after baseline).
        let new = [agent("z", 3, "new-proj")]
        let t = detectTransitions(old: ["a": .running], new: new, hasBaseline: true)
        XCTAssertEqual(t, [.needsInput(project: "new-proj")])
    }
}
