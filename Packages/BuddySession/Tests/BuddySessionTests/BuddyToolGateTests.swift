import XCTest
@testable import BuddySession

final class BuddyToolGateTests: XCTestCase {
    func testStartTourOnlyAllowedFromLive() {
        XCTAssertNil(BuddyToolGate.rejection(for: "start_tour", mode: .live))
        XCTAssertEqual(BuddyToolGate.rejection(for: "start_tour", mode: .guiding), .sessionBusy)
        XCTAssertEqual(BuddyToolGate.rejection(for: "start_tour", mode: .settling), .sessionBusy)
        XCTAssertEqual(BuddyToolGate.rejection(for: "start_tour", mode: .touringActive), .tourAlreadyActive)
        XCTAssertEqual(BuddyToolGate.rejection(for: "start_tour", mode: .touringPaused), .tourAlreadyActive)
    }

    func testPointToElementRejectedDuringTour() {
        XCTAssertNil(BuddyToolGate.rejection(for: "point_to_element", mode: .live))
        XCTAssertNil(BuddyToolGate.rejection(for: "point_to_element", mode: .guiding))
        XCTAssertEqual(BuddyToolGate.rejection(for: "point_to_element", mode: .touringActive), .tourActive)
        XCTAssertEqual(BuddyToolGate.rejection(for: "point_to_element", mode: .touringPaused), .tourActive)
    }

    func testResumeTourOnlyAllowedWhenPaused() {
        XCTAssertNil(BuddyToolGate.rejection(for: "resume_tour", mode: .touringPaused))
        XCTAssertEqual(BuddyToolGate.rejection(for: "resume_tour", mode: .touringActive), .tourNotPaused)
        XCTAssertEqual(BuddyToolGate.rejection(for: "resume_tour", mode: .live), .noActiveTour)
    }

    func testStopTourOnlyAllowedDuringTour() {
        XCTAssertNil(BuddyToolGate.rejection(for: "stop_tour", mode: .touringActive))
        XCTAssertNil(BuddyToolGate.rejection(for: "stop_tour", mode: .touringPaused))
        XCTAssertEqual(BuddyToolGate.rejection(for: "stop_tour", mode: .live), .noActiveTour)
    }
}
