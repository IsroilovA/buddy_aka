import XCTest
import BuddySession
import BuddyUIModel
@testable import BuddyLessons

final class LessonParserTests: XCTestCase {
    func testParseMinimalLesson() throws {
        let md = """
        ---
        id: demo.minimal
        title: Minimal demo
        app:
          bundle_id: com.example.foo
        ---

        # Minimal demo

        Lead-in prose.

        ## Step 1 — Do the thing

        > Click the button.

        **Teach:** Buttons do things.

        ```yaml
        expect:
          match:
            role: button
            label: "Go"
          advance_when: focused_element_changes

        ```

        ## Wrap-up

        > Nice work.
        """
        let lesson = try LessonParser.parse(md)
        XCTAssertEqual(lesson.id, "demo.minimal")
        XCTAssertEqual(lesson.title, "Minimal demo")
        XCTAssertEqual(lesson.app, .bundleID("com.example.foo"))
        XCTAssertEqual(lesson.steps.count, 1)
        XCTAssertEqual(lesson.steps[0].userInstruction, "Click the button.")
        XCTAssertEqual(lesson.steps[0].teach, "Buttons do things.")
        XCTAssertEqual(lesson.steps[0].expect?.advanceWhen, .focusedElementChanges)
        XCTAssertEqual(lesson.steps[0].expect?.match?.role, .button)
        XCTAssertEqual(lesson.steps[0].expect?.match?.label, "Go")
        XCTAssertEqual(lesson.wrapup, "Nice work.")
    }

    func testParseValueAdvanceConditions() throws {
        let md = """
        ---
        id: demo.value
        title: Value
        app:
          url_match: example.com
        ---

        ## Step 1 — Type
        > Type stuff.
        ```yaml
        expect:
          match:
            role: text_field
            label_contains: "Formula"
          advance_when: value_contains
          advance_value: ")"
        ```
        """
        let lesson = try LessonParser.parse(md)
        XCTAssertEqual(lesson.app, .urlMatch("example.com"))
        XCTAssertEqual(lesson.steps[0].expect?.advanceWhen, .valueContains(")"))
    }

    func testParseAnyOfMatcher() throws {
        let md = """
        ---
        id: demo.anyof
        title: AnyOf
        app:
          bundle_id: com.example.foo
        ---

        ## Step 1 — Click
        > Click.
        ```yaml
        expect:
          match:
            role: button
            any_of:
              - { label: "Insert" }
              - { label: "Вставка" }
          advance_when: focused_element_changes
        ```
        """
        let lesson = try LessonParser.parse(md)
        let any = lesson.steps[0].expect?.match?.anyOf
        XCTAssertEqual(any?.count, 2)
        XCTAssertEqual(any?[0].label, "Insert")
        XCTAssertEqual(any?[1].label, "Вставка")
    }

    func testMissingFrontmatterThrows() {
        XCTAssertThrowsError(try LessonParser.parse("# no frontmatter"))
    }

    func testParseUrlContainsAdvance() throws {
        let md = """
        ---
        id: demo.url
        title: URL
        app:
          url_match: example.com
        ---

        ## Step 1 — Navigate
        > Type the URL and press Return.
        ```yaml
        expect:
          advance_when: url_contains
          advance_value: "example.com/dashboard"

        ```
        """
        let lesson = try LessonParser.parse(md)
        XCTAssertEqual(lesson.steps[0].expect?.advanceWhen, .urlContains("example.com/dashboard"))
    }

    func testParseScopeInMatcher() throws {
        let md = """
        ---
        id: demo.scope
        title: Scope
        app:
          bundle_id: com.apple.systempreferences
        ---

        ## Step 1 — Click Apple menu
        > Click the Apple menu.
        ```yaml
        expect:
          match:
            scope: menu_bar
            any_of:
              - { scope: menu_bar, role: menu_item, label: "" }
              - { scope: dock, label_contains: "System Settings" }
          advance_when: window_changes
        ```
        """
        let lesson = try LessonParser.parse(md)
        XCTAssertEqual(lesson.steps[0].expect?.match?.scope, .menuBar)
        let any = lesson.steps[0].expect?.match?.anyOf
        XCTAssertEqual(any?[0].scope, .menuBar)
        XCTAssertEqual(any?[1].scope, .dock)
    }

    func testUnknownAdvanceThrows() {
        let md = """
        ---
        id: demo.bad
        title: Bad
        app:
          bundle_id: com.example.foo
        ---

        ## Step 1 — X
        > Do it.
        ```yaml
        expect:
          advance_when: jazzhands
        ```
        """
        XCTAssertThrowsError(try LessonParser.parse(md))
    }
}
