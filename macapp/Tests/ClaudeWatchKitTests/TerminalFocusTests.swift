import XCTest
@testable import ClaudeWatchKit

final class TerminalFocusTests: XCTestCase {
    func testVSCodeActivatesByBundleId() {
        let s = terminalFocusScript(term: "vscode", tty: "/dev/ttys008")
        XCTAssertEqual(s, "if application id \"com.microsoft.VSCode\" is running then "
            + "tell application id \"com.microsoft.VSCode\" to activate")
    }

    func testITermScriptMatchesTTY() {
        let s = terminalFocusScript(term: "iTerm.app", tty: "/dev/ttys003")
        XCTAssertNotNil(s)
        XCTAssertTrue(s!.contains("iTerm"))
        XCTAssertTrue(s!.contains("(tty of s) is \"/dev/ttys003\""))
    }

    func testTerminalScriptMatchesTTY() {
        let s = terminalFocusScript(term: "Apple_Terminal", tty: "/dev/ttys004")
        XCTAssertNotNil(s)
        XCTAssertTrue(s!.contains("Terminal"))
        XCTAssertTrue(s!.contains("(tty of t) is \"/dev/ttys004\""))
    }

    func testUnknownTermWithTTYTriesBoth() {
        let s = terminalFocusScript(term: "Hyper", tty: "/dev/ttys009")
        XCTAssertNotNil(s)
        XCTAssertTrue(s!.contains("iTerm"))
        XCTAssertTrue(s!.contains("Terminal"))
        XCTAssertTrue(s!.contains("/dev/ttys009"))
    }

    func testUnknownTermNoTTYReturnsNil() {
        XCTAssertNil(terminalFocusScript(term: nil, tty: nil))
        XCTAssertNil(terminalFocusScript(term: "Hyper", tty: nil))
    }

    func testKnownTermNoTTYActivatesApp() {
        XCTAssertEqual(terminalFocusScript(term: "iTerm.app", tty: nil),
                       "if application \"iTerm\" is running then tell application \"iTerm\" to activate")
    }

    func testUnsafeTTYIsRejectedAndFallsBackToActivate() {
        // An injection attempt must not reach the AppleScript literal.
        let evil = "/dev/ttys003\" then do shell script \"open -a Calculator"
        let s = terminalFocusScript(term: "iTerm.app", tty: evil)
        XCTAssertEqual(s, "if application \"iTerm\" is running then tell application \"iTerm\" to activate")
        XCTAssertFalse(s!.contains("do shell script"))
    }

    func testSafeTTYValidation() {
        XCTAssertTrue(isSafeTTY("/dev/ttys003"))
        XCTAssertTrue(isSafeTTY("/dev/tty"))
        XCTAssertFalse(isSafeTTY("/dev/ttys003\""))
        XCTAssertFalse(isSafeTTY("ttys003"))
        XCTAssertFalse(isSafeTTY("/dev/ttys 003"))
    }
}
