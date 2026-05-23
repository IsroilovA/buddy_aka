import XCTest
@testable import BuddySession

final class BuddyRuntimeEventTests: XCTestCase {
    func testTourStepEncodesAsJsonWithEscapedLabel() throws {
        let step = TourStep(elementID: "e_1", label: "Line \"one\"\nLine two", role: "button")
        let event = BuddyRuntimeEvent.tourStep(index: 1, total: 3, step: step)
        let data = try JSONEncoder().encode(event)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["type"] as? String, "tour_step")
        XCTAssertEqual(object["index"] as? Int, 1)
        XCTAssertEqual(object["total"] as? Int, 3)
        XCTAssertEqual(object["element_id"] as? String, "e_1")
        XCTAssertEqual(object["label"] as? String, "Line \"one\"\nLine two")
        XCTAssertEqual(object["role"] as? String, "button")
    }

    func testTourAbortedEncodesReason() throws {
        let event = BuddyRuntimeEvent.tourAborted(reason: .appChanged)
        let data = try JSONEncoder().encode(event)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["type"] as? String, "tour_aborted")
        XCTAssertEqual(object["reason"] as? String, "app_changed")
    }
}
