import XCTest
@testable import BuddySafariDOM

final class AppleScriptBridgeTests: XCTestCase {
    func testEscape_preservesPlainText() {
        XCTAssertEqual(
            AppleScriptBridge.escape(forAppleScriptString: "hello world"),
            "hello world"
        )
    }

    func testEscape_doublesBackslashes() {
        XCTAssertEqual(
            AppleScriptBridge.escape(forAppleScriptString: #"a\b"#),
            #"a\\b"#
        )
    }

    func testEscape_escapesDoubleQuotes() {
        XCTAssertEqual(
            AppleScriptBridge.escape(forAppleScriptString: #"say "hi""#),
            #"say \"hi\""#
        )
    }

    func testEscape_convertsControlChars() {
        XCTAssertEqual(
            AppleScriptBridge.escape(forAppleScriptString: "a\nb\tc\rd"),
            #"a\nb\tc\rd"#
        )
    }

    func testEscape_backslashBeforeQuote_orderMatters() {
        // Reads "\" - a literal backslash followed by a literal quote - and
        // must produce a 4-char AppleScript-safe sequence \\\". If we replaced
        // \" first we'd double-escape the backslash later.
        XCTAssertEqual(
            AppleScriptBridge.escape(forAppleScriptString: #"\""#),
            #"\\\""#
        )
    }
}
