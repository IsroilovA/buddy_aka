import ApplicationServices
import BuddyAccessibility
import CoreGraphics
import XCTest
@testable import BuddySession

final class GuidanceSignalControllerTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 100, width: 80, height: 40)

    private func handle() -> AXElementHandle {
        AXElementHandle(AXUIElementCreateSystemWide())
    }

    func testResetReturnsToIdle() {
        var c = GuidanceSignalController()
        c.startGuiding(elementID: "x", frame: frame)
        c.reset()
        XCTAssertEqual(c.handleMouseClick(CGPoint(x: 140, y: 120)), .none)
    }

    func testMouseClickWhileIdleIsNone() {
        var c = GuidanceSignalController()
        XCTAssertEqual(c.handleMouseClick(CGPoint(x: 0, y: 0)), .none)
    }

    func testMouseClickInsideTargetSchedulesSettle() {
        var c = GuidanceSignalController()
        c.startGuiding(elementID: "x", frame: frame)
        XCTAssertEqual(c.handleMouseClick(CGPoint(x: 140, y: 120)), .scheduleSettle)
        XCTAssertEqual(c.finishSettling(), .send(.targetClicked))
    }

    func testMouseClickOutsideTarget() {
        var c = GuidanceSignalController()
        c.startGuiding(elementID: "x", frame: frame)
        XCTAssertEqual(c.handleMouseClick(CGPoint(x: 500, y: 500)), .scheduleSettle)
        XCTAssertEqual(c.finishSettling(), .send(.userClickedElsewhere))
    }

    func testAXFocusChangedWhileGuidingSchedulesSettle() {
        var c = GuidanceSignalController()
        c.startGuiding(elementID: "x", frame: frame)
        XCTAssertEqual(c.handleAXEvent(.focusedElementChanged(handle())), .scheduleSettle)
        XCTAssertEqual(c.finishSettling(), .send(.screenChanged))
    }

    func testAXLayoutChangedIsNotMeaningful() {
        var c = GuidanceSignalController()
        c.startGuiding(elementID: "x", frame: frame)
        XCTAssertEqual(c.handleAXEvent(.layoutChanged), .none)
    }

    func testTimeoutWhileGuidingSendsIdle() {
        var c = GuidanceSignalController()
        c.startGuiding(elementID: "x", frame: frame)
        XCTAssertEqual(c.handleTimeout(), .send(.idleTimeout))
    }

    func testTimeoutWhileIdleIsNone() {
        var c = GuidanceSignalController()
        XCTAssertEqual(c.handleTimeout(), .none)
    }

    func testTimeoutWhileSettlingIsNone() {
        var c = GuidanceSignalController()
        c.startGuiding(elementID: "x", frame: frame)
        _ = c.handleMouseClick(CGPoint(x: 140, y: 120))
        XCTAssertEqual(c.handleTimeout(), .none)
    }

    func testFinishSettlingTargetClickWithoutAXSendsTargetClicked() {
        var c = GuidanceSignalController()
        c.startGuiding(elementID: "x", frame: frame)
        _ = c.handleMouseClick(CGPoint(x: 140, y: 120))
        XCTAssertEqual(c.finishSettling(), .send(.targetClicked))
    }

    func testFinishSettlingTargetClickWithAXSendsScreenChanged() {
        var c = GuidanceSignalController()
        c.startGuiding(elementID: "x", frame: frame)
        _ = c.handleMouseClick(CGPoint(x: 140, y: 120))
        _ = c.handleAXEvent(.focusedElementChanged(handle()))
        XCTAssertEqual(c.finishSettling(), .send(.screenChanged))
    }

    func testFinishSettlingOffTargetClickSendsClickedElsewhere() {
        var c = GuidanceSignalController()
        c.startGuiding(elementID: "x", frame: frame)
        _ = c.handleMouseClick(CGPoint(x: 500, y: 500))
        XCTAssertEqual(c.finishSettling(), .send(.userClickedElsewhere))
    }

    func testFinishSettlingAXProgressSendsScreenChanged() {
        var c = GuidanceSignalController()
        c.startGuiding(elementID: "x", frame: frame)
        _ = c.handleAXEvent(.focusedElementChanged(handle()))
        XCTAssertEqual(c.finishSettling(), .send(.screenChanged))
    }
}
