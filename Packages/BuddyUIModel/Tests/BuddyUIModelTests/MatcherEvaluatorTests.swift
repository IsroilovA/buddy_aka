import XCTest
@testable import BuddyUIModel

final class MatcherEvaluatorTests: XCTestCase {
    private func node(
        id: String = "1",
        role: UIElementRole = .button,
        scope: UIElementScope = .appWindow,
        label: String? = nil,
        identifier: String? = nil,
        frame: UIFrame = UIFrame(x: 0, y: 0, w: 100, h: 30)
    ) -> UIElementNode {
        var meta: [String: String] = [:]
        if let identifier { meta["identifier"] = identifier }
        return UIElementNode(
            id: id,
            source: .ax,
            scope: scope,
            role: role,
            label: label,
            enabled: true,
            focused: false,
            frame: frame,
            metadata: meta
        )
    }

    func testMatchByRoleAndLabel() {
        let el = node(label: "Insert")
        XCTAssertTrue(MatcherEvaluator.matches(el, ElementMatcher(role: .button, label: "Insert")))
        XCTAssertFalse(MatcherEvaluator.matches(el, ElementMatcher(role: .link, label: "Insert")))
    }

    func testLabelCaseInsensitive() {
        let el = node(label: "Insert")
        XCTAssertTrue(MatcherEvaluator.matches(el, ElementMatcher(label: "insert")))
    }

    func testLabelContains() {
        let el = node(label: "Formula bar input")
        XCTAssertTrue(MatcherEvaluator.matches(el, ElementMatcher(labelContains: "Formula")))
        XCTAssertFalse(MatcherEvaluator.matches(el, ElementMatcher(labelContains: "Histogram")))
    }

    func testIdentifierExact() {
        let el = node(identifier: "btn-go")
        XCTAssertTrue(MatcherEvaluator.matches(el, ElementMatcher(identifier: "btn-go")))
    }

    func testAnyOfCombinator() {
        let el = node(label: "Вставка")
        let matcher = ElementMatcher(anyOf: [
            ElementMatcher(label: "Insert"),
            ElementMatcher(label: "Вставка"),
            ElementMatcher(label: "Qo'shish")
        ])
        XCTAssertTrue(MatcherEvaluator.matches(el, matcher))
    }

    func testEmptyMatcherDoesNotMatch() {
        let el = node()
        XCTAssertFalse(MatcherEvaluator.matches(el, ElementMatcher()))
    }

    func testScopeFilters() {
        let menu = node(id: "m", scope: .menuBar, label: "Apple")
        let dock = node(id: "d", scope: .dock, label: "Apple")
        let win  = node(id: "w", scope: .appWindow, label: "Apple")
        let snap = UISnapshot(elements: [menu, dock, win])
        let hits = MatcherEvaluator.findAll(in: snap, matching: ElementMatcher(scope: .menuBar, label: "Apple"))
        XCTAssertEqual(hits.map(\.id), ["m"])
    }

    func testScopeOnlyMatcherIsAllowed() {
        let menu = node(id: "m", scope: .menuBar)
        XCTAssertTrue(MatcherEvaluator.matches(menu, ElementMatcher(scope: .menuBar)))
    }

    func testFindBestPrefersLargestFrame() {
        let small = node(id: "a", label: "Save", frame: UIFrame(x: 0, y: 0, w: 20, h: 20))
        let big = node(id: "b", label: "Save", frame: UIFrame(x: 0, y: 0, w: 200, h: 60))
        let snap = UISnapshot(elements: [small, big])
        let hit = MatcherEvaluator.findBest(in: snap, matching: ElementMatcher(label: "Save"))
        XCTAssertEqual(hit?.id, "b")
    }
}
