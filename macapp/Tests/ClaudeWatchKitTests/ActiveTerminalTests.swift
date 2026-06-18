import XCTest
@testable import ClaudeWatchKit

final class ActiveTerminalTests: XCTestCase {
    private func agent(_ project: String, _ term: String?) -> Agent {
        Agent(id: "1", project: project, state: 3, ageSeconds: 0, term: term)
    }

    func testActiveWhenFrontmostTerminalAndTitleHasProject() {
        let a = agent("claude-watchh", "vscode")
        XCTAssertTrue(agentIsActivelyViewed(
            a, frontmostBundleId: "com.microsoft.VSCode",
            focusedTitle: "main.swift — claude-watchh"))
    }

    func testNotActiveWhenDifferentAppFrontmost() {
        let a = agent("claude-watchh", "vscode")
        XCTAssertFalse(agentIsActivelyViewed(
            a, frontmostBundleId: "com.apple.Safari", focusedTitle: "claude-watchh"))
    }

    func testNotActiveWhenFocusedWindowIsAnotherProject() {
        let a = agent("claude-watchh", "vscode")
        XCTAssertFalse(agentIsActivelyViewed(
            a, frontmostBundleId: "com.microsoft.VSCode",
            focusedTitle: "index.ts — other-project"))
    }

    func testNotActiveWhenTitleMissing() {
        let a = agent("claude-watchh", "vscode")
        XCTAssertFalse(agentIsActivelyViewed(
            a, frontmostBundleId: "com.microsoft.VSCode", focusedTitle: nil))
    }

    func testUnknownTerminalNeverActive() {
        let a = agent("claude-watchh", nil)
        XCTAssertFalse(agentIsActivelyViewed(
            a, frontmostBundleId: nil, focusedTitle: "claude-watchh"))
    }
}
