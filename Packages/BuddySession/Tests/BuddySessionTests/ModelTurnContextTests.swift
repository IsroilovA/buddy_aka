import XCTest
@testable import BuddySession

final class ModelTurnContextTests: XCTestCase {
    func testInitDefaults() {
        let ctx = ModelTurnContext()
        XCTAssertEqual(ctx.phase, .idle)
        XCTAssertEqual(ctx.pendingForInspection, [])
    }

    func testEnqueueWhileIdleSendsNowSingleEnvelope() {
        var ctx = ModelTurnContext()
        XCTAssertEqual(ctx.enqueue(.sessionStarted),
                       .sendNow("[BUDDY_SIGNALS] session_started"))
        XCTAssertEqual(ctx.enqueue(.targetClicked),
                       .sendNow("[BUDDY_SIGNALS] target_clicked"))
        XCTAssertEqual(ctx.pendingForInspection, [])
    }

    func testEnqueueWhileSpeakingBuffersEdgeSignals() {
        var ctx = ModelTurnContext()
        ctx.phaseChanged(to: .speaking)
        XCTAssertEqual(ctx.enqueue(.targetClicked), .buffered)
        XCTAssertEqual(ctx.enqueue(.userClickedElsewhere), .buffered)
        XCTAssertEqual(ctx.pendingForInspection, [.targetClicked, .userClickedElsewhere])
    }

    func testIdleTimeoutDroppedWhileSpeaking() {
        var ctx = ModelTurnContext()
        ctx.phaseChanged(to: .speaking)
        XCTAssertEqual(ctx.enqueue(.idleTimeout), .dropped(reason: .modelSpeaking))
        XCTAssertEqual(ctx.pendingForInspection, [])
    }

    func testConsecutiveIdenticalEdgeSignalDropped() {
        var ctx = ModelTurnContext()
        ctx.phaseChanged(to: .speaking)
        XCTAssertEqual(ctx.enqueue(.targetClicked), .buffered)
        XCTAssertEqual(ctx.enqueue(.targetClicked), .dropped(reason: .consecutiveDuplicate))
        XCTAssertEqual(ctx.pendingForInspection, [.targetClicked])
    }

    func testScreenChangedCoalescesToOne() {
        var ctx = ModelTurnContext()
        ctx.phaseChanged(to: .speaking)
        XCTAssertEqual(ctx.enqueue(.screenChanged), .buffered)
        XCTAssertEqual(ctx.enqueue(.screenChanged), .buffered)
        XCTAssertEqual(ctx.pendingForInspection, [.screenChanged])
    }

    func testInterleavedTargetAndScreenChanged() {
        var ctx = ModelTurnContext()
        ctx.phaseChanged(to: .speaking)
        _ = ctx.enqueue(.targetClicked)
        _ = ctx.enqueue(.screenChanged)
        _ = ctx.enqueue(.screenChanged)
        XCTAssertEqual(ctx.pendingForInspection, [.targetClicked, .screenChanged])
    }

    func testBufferOverflowDropsOldest() {
        var ctx = ModelTurnContext(capacity: 3)
        ctx.phaseChanged(to: .speaking)
        XCTAssertEqual(ctx.enqueue(.targetClicked), .buffered)
        XCTAssertEqual(ctx.enqueue(.userClickedElsewhere), .buffered)
        XCTAssertEqual(ctx.enqueue(.targetClicked), .buffered)
        XCTAssertEqual(ctx.enqueue(.userClickedElsewhere),
                       .dropped(reason: .bufferOverflow))
        XCTAssertEqual(ctx.pendingForInspection,
                       [.userClickedElsewhere, .targetClicked, .userClickedElsewhere])
    }

    func testDrainOnTurnCompletePopulated() {
        var ctx = ModelTurnContext()
        ctx.phaseChanged(to: .speaking)
        _ = ctx.enqueue(.targetClicked)
        _ = ctx.enqueue(.screenChanged)
        XCTAssertEqual(ctx.drainOnTurnComplete(),
                       "[BUDDY_SIGNALS] target_clicked, screen_changed")
        XCTAssertEqual(ctx.phase, .idle)
        XCTAssertEqual(ctx.pendingForInspection, [])
    }

    func testDrainOnTurnCompleteEmpty() {
        var ctx = ModelTurnContext()
        ctx.phaseChanged(to: .speaking)
        XCTAssertNil(ctx.drainOnTurnComplete())
        XCTAssertEqual(ctx.phase, .idle)
    }
}
