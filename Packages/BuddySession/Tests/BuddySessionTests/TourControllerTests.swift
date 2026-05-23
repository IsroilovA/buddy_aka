import XCTest
@testable import BuddySession

@MainActor
final class TourControllerTests: XCTestCase {
    private func makeSteps(_ count: Int) -> [TourStep] {
        (0..<count).map { i in
            TourStep(elementID: "e_\(i)", label: "Label \(i)", role: "button")
        }
    }

    func testStartWithEmptyStepsFails() {
        var c = TourController()
        XCTAssertEqual(c.start(steps: []), .empty)
        XCTAssertEqual(c.state, .idle)
    }

    func testStartTransitionsToActiveAtIndexZero() {
        var c = TourController()
        let steps = makeSteps(3)
        let res = c.start(steps: steps)
        XCTAssertEqual(res, .started(initialStep: steps[0], total: 3))
        XCTAssertEqual(c.state, .active(currentIndex: 0, total: 3))
    }

    func testStartWhileActiveRejected() {
        var c = TourController()
        let steps = makeSteps(2)
        _ = c.start(steps: steps)
        XCTAssertEqual(c.start(steps: makeSteps(4)), .alreadyActive)
        XCTAssertEqual(c.state, .active(currentIndex: 0, total: 2))
    }

    func testTickAdvancesThroughSteps() {
        var c = TourController()
        let steps = makeSteps(3)
        _ = c.start(steps: steps)
        XCTAssertEqual(c.tick(), .step(index: 1, total: 3, step: steps[1]))
        XCTAssertEqual(c.state, .active(currentIndex: 1, total: 3))
        XCTAssertEqual(c.tick(), .step(index: 2, total: 3, step: steps[2]))
        XCTAssertEqual(c.state, .active(currentIndex: 2, total: 3))
    }

    func testTickPastLastStepReturnsComplete() {
        var c = TourController()
        _ = c.start(steps: makeSteps(2))
        _ = c.tick()
        XCTAssertEqual(c.tick(), .complete)
        XCTAssertEqual(c.state, .idle)
    }

    func testTickWhileIdleReturnsIdle() {
        var c = TourController()
        XCTAssertEqual(c.tick(), .idle)
    }

    func testStopClearsStateMidTour() {
        var c = TourController()
        _ = c.start(steps: makeSteps(5))
        _ = c.tick()
        c.stop()
        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(c.tick(), .idle)
    }

    func testRestartAfterStop() {
        var c = TourController()
        _ = c.start(steps: makeSteps(2))
        c.stop()
        let secondSteps = makeSteps(4)
        XCTAssertEqual(c.start(steps: secondSteps), .started(initialStep: secondSteps[0], total: 4))
        XCTAssertEqual(c.state, .active(currentIndex: 0, total: 4))
    }
}
