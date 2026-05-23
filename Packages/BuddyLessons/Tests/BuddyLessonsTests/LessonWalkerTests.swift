import XCTest
import BuddyAccessibility
import BuddySession
import BuddyUIModel
@testable import BuddyLessons

final class LessonWalkerTests: XCTestCase {
    private func minimalLesson(steps: [LessonStep]? = nil) -> Lesson {
        let resolved = steps ?? [
            LessonStep(
                id: 0,
                userInstruction: "Click X",
                expect: StepExpectation(
                    match: ElementMatcher(role: .button, label: "X"),
                    advanceWhen: .focusedElementChanges
                )
            ),
            LessonStep(
                id: 1,
                userInstruction: "Click Y",
                expect: StepExpectation(
                    match: ElementMatcher(role: .button, label: "Y"),
                    advanceWhen: .focusedElementChanges
                )
            )
        ]
        return Lesson(
            id: "demo",
            title: "Demo",
            app: .bundleID("com.example.foo"),
            steps: resolved
        )
    }

    func testStartsAtStepZero() {
        var walker = LessonWalker(lesson: minimalLesson())
        XCTAssertEqual(walker.phase, .awaitingStep(stepIndex: 0))
        let effects = walker.didStart(currentSnapshot: nil)
        XCTAssertTrue(effects.contains(.emitSignal(.lessonStepCompleted)))
    }

    func testValueContainsAdvancesOnSnapshot() {
        let lesson = Lesson(
            id: "demo",
            title: "Demo",
            app: .urlMatch("example.com"),
            steps: [
                LessonStep(
                    id: 0,
                    userInstruction: "Type",
                    expect: StepExpectation(
                        match: ElementMatcher(role: .textField),
                        advanceWhen: .valueContains(")")
                    )
                ),
                LessonStep(
                    id: 1,
                    userInstruction: "Done",
                    expect: StepExpectation(advanceWhen: .focusedElementChanges)
                )
            ]
        )
        var walker = LessonWalker(lesson: lesson)
        _ = walker.didStart(currentSnapshot: nil)
        let focused = UIElementNode(
            id: "1", source: .ax, role: .textField,
            label: nil, value: "=SUM(1,2)", hasValue: true,
            enabled: true, focused: true,
            frame: UIFrame(x: 0, y: 0, w: 10, h: 10)
        )
        let snap = UISnapshot(elements: [focused])
        let effects = walker.observe(snapshot: snap)
        XCTAssertEqual(walker.phase, .awaitingStep(stepIndex: 1))
        XCTAssertTrue(effects.contains(.emitSignal(.lessonStepCompleted)))
    }

    func testUrlContainsAdvancesOnSnapshot() {
        let lesson = Lesson(
            id: "demo",
            title: "Demo",
            app: .bundleID("com.apple.Safari"),
            steps: [
                LessonStep(
                    id: 0,
                    userInstruction: "Navigate",
                    expect: StepExpectation(advanceWhen: .urlContains("docs.google.com/spreadsheets"))
                ),
                LessonStep(
                    id: 1,
                    userInstruction: "Done",
                    expect: StepExpectation(advanceWhen: .focusedElementChanges)
                )
            ]
        )
        var walker = LessonWalker(lesson: lesson)
        _ = walker.didStart(currentSnapshot: nil)

        let snapBefore = UISnapshot(app: "com.apple.Safari", url: "https://google.com")
        _ = walker.observe(snapshot: snapBefore)
        XCTAssertEqual(walker.phase, .awaitingStep(stepIndex: 0))

        let snapAfter = UISnapshot(app: "com.apple.Safari", url: "https://docs.google.com/spreadsheets/d/abc")
        _ = walker.observe(snapshot: snapAfter)
        XCTAssertEqual(walker.phase, .awaitingStep(stepIndex: 1))
    }

    func testFinishesAfterLastStep() {
        // Both steps use focusedElementChanges — look-ahead sees the next step
        // matches the same event, so a single event fast-forwards to finished.
        var walker = LessonWalker(lesson: minimalLesson())
        _ = walker.didStart(currentSnapshot: nil)
        let handle = AXElementHandle(AXUIElementCreateSystemWide())
        _ = walker.handle(axEvent: .focusedElementChanged(handle), currentSnapshot: nil)
        XCTAssertEqual(walker.phase, .finished)
    }

    func testExitTransitionsToExited() {
        var walker = LessonWalker(lesson: minimalLesson())
        _ = walker.didStart(currentSnapshot: nil)
        let effects = walker.exit()
        XCTAssertEqual(walker.phase, .exited)
        XCTAssertTrue(effects.contains(.emitSignal(.lessonExited)))
        XCTAssertTrue(effects.contains(.finishedWalk))
    }

    // MARK: - Look-ahead tests

    func testLookAheadFastForwardsWhenNextStepMatches() {
        let lesson = Lesson(
            id: "demo",
            title: "Demo",
            app: .bundleID("com.apple.Safari"),
            steps: [
                LessonStep(
                    id: 0,
                    userInstruction: "Click Safari",
                    expect: StepExpectation(advanceWhen: .focusedElementChanges)
                ),
                LessonStep(
                    id: 1,
                    userInstruction: "Click URL bar",
                    expect: StepExpectation(advanceWhen: .focusedElementChanges)
                ),
                LessonStep(
                    id: 2,
                    userInstruction: "Navigate to Sheets",
                    expect: StepExpectation(advanceWhen: .urlContains("docs.google.com/spreadsheets"))
                ),
                LessonStep(
                    id: 3,
                    userInstruction: "Done",
                    expect: StepExpectation(advanceWhen: .focusedElementChanges)
                )
            ]
        )
        var walker = LessonWalker(lesson: lesson)
        _ = walker.didStart(currentSnapshot: nil)
        XCTAssertEqual(walker.phase, .awaitingStep(stepIndex: 0))

        // Step 0 expects focusedElementChanges, step 1 also expects focusedElementChanges.
        // Look-ahead: first focusedElementChanged on step 0 sees step 1 matches too → jump to step 2.
        let handle = AXElementHandle(AXUIElementCreateSystemWide())
        _ = walker.handle(axEvent: .focusedElementChanged(handle), currentSnapshot: nil)
        XCTAssertEqual(walker.phase, .awaitingStep(stepIndex: 2))

        // Now on step 2 (urlContains). Provide a matching URL snapshot.
        // Look-ahead checks step 3 (focusedElementChanges) — event-based, won't match in observe().
        // Current step 2 matches → advance to step 3.
        let snap = UISnapshot(app: "com.apple.Safari", url: "https://docs.google.com/spreadsheets/d/abc")
        let effects = walker.observe(snapshot: snap)
        XCTAssertEqual(walker.phase, .awaitingStep(stepIndex: 3))
        XCTAssertTrue(effects.contains(.emitSignal(.lessonStepCompleted)))
    }

    func testLookAheadEventBasedFastForwards() {
        let lesson = Lesson(
            id: "demo",
            title: "Demo",
            app: .bundleID("com.example.foo"),
            steps: [
                LessonStep(
                    id: 0,
                    userInstruction: "Wait for window",
                    expect: StepExpectation(advanceWhen: .windowChanges)
                ),
                LessonStep(
                    id: 1,
                    userInstruction: "Click button",
                    expect: StepExpectation(advanceWhen: .focusedElementChanges)
                ),
                LessonStep(
                    id: 2,
                    userInstruction: "Done",
                    expect: StepExpectation(advanceWhen: .focusedElementChanges)
                )
            ]
        )
        var walker = LessonWalker(lesson: lesson)
        _ = walker.didStart(currentSnapshot: nil)
        XCTAssertEqual(walker.phase, .awaitingStep(stepIndex: 0))

        // A focusedElementChanged event arrives while on step 0 (which expects windowChanges).
        // But step 1 (the next step) expects focusedElementChanges — look-ahead should match.
        let handle = AXElementHandle(AXUIElementCreateSystemWide())
        let effects = walker.handle(axEvent: .focusedElementChanged(handle), currentSnapshot: nil)
        // Should fast-forward past step 1 to step 2.
        XCTAssertEqual(walker.phase, .awaitingStep(stepIndex: 2))
        XCTAssertTrue(effects.contains(.emitSignal(.lessonStepCompleted)))
    }

    // MARK: - Open-loop tests

    func testOpenLoopDidStartNoOp() {
        let lesson = Lesson(id: "adhoc", title: "Ad-hoc", app: .bundleID(""), steps: [])
        var walker = LessonWalker(lesson: lesson)
        XCTAssertTrue(lesson.isOpenLoop)
        let effects = walker.didStart(currentSnapshot: nil)
        XCTAssertTrue(effects.isEmpty)
    }

    func testOpenLoopAdvanceTo() {
        let lesson = Lesson(id: "adhoc", title: "Ad-hoc", app: .bundleID(""), steps: [])
        var walker = LessonWalker(lesson: lesson)
        _ = walker.didStart(currentSnapshot: nil)

        let effects = walker.advanceTo(stepIndex: 1)
        XCTAssertEqual(walker.phase, .awaitingStep(stepIndex: 1))
        XCTAssertTrue(effects.contains(.emitSignal(.lessonStepCompleted)))
        XCTAssertTrue(effects.contains(where: {
            if case .emitEvent(.lessonStepAdvanced(index: 1, total: nil, instruction: "", teach: nil)) = $0 {
                return true
            }
            return false
        }))
    }

    func testOpenLoopRequestFinish() {
        let lesson = Lesson(id: "adhoc", title: "Ad-hoc", app: .bundleID(""), steps: [])
        var walker = LessonWalker(lesson: lesson)
        _ = walker.didStart(currentSnapshot: nil)

        let effects = walker.requestFinish()
        XCTAssertEqual(walker.phase, .finished)
        XCTAssertTrue(effects.contains(.emitSignal(.lessonFinished)))
        XCTAssertTrue(effects.contains(.finishedWalk))
    }

    func testOpenLoopObserveNoOp() {
        let lesson = Lesson(id: "adhoc", title: "Ad-hoc", app: .bundleID(""), steps: [])
        var walker = LessonWalker(lesson: lesson)
        _ = walker.didStart(currentSnapshot: nil)

        let snap = UISnapshot(elements: [])
        let effects = walker.observe(snapshot: snap)
        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(walker.phase, .awaitingStep(stepIndex: 0))
    }

    // MARK: - Model-driven advance (curated)

    func testAdvanceToSpecificStep() {
        var walker = LessonWalker(lesson: minimalLesson())
        _ = walker.didStart(currentSnapshot: nil)
        XCTAssertEqual(walker.phase, .awaitingStep(stepIndex: 0))

        let effects = walker.advanceTo(stepIndex: 1)
        XCTAssertEqual(walker.phase, .awaitingStep(stepIndex: 1))
        XCTAssertTrue(effects.contains(.emitSignal(.lessonStepCompleted)))
    }

    func testAdvanceToOutOfRangeReturnsEmpty() {
        var walker = LessonWalker(lesson: minimalLesson())
        _ = walker.didStart(currentSnapshot: nil)

        let effects = walker.advanceTo(stepIndex: 99)
        XCTAssertTrue(effects.isEmpty)
    }

    func testAdvanceToBackward() {
        let lesson = Lesson(
            id: "demo",
            title: "Demo",
            app: .bundleID("com.example.foo"),
            steps: [
                LessonStep(id: 0, userInstruction: "A", expect: StepExpectation(advanceWhen: .focusedElementChanges)),
                LessonStep(id: 1, userInstruction: "B", expect: StepExpectation(advanceWhen: .windowChanges)),
                LessonStep(id: 2, userInstruction: "C", expect: StepExpectation(advanceWhen: .focusedElementChanges))
            ]
        )
        var walker = LessonWalker(lesson: lesson)
        _ = walker.didStart(currentSnapshot: nil)
        // Step 0: focusedElementChanges. Step 1: windowChanges (different).
        // focusedElementChanged on step 0: look-ahead checks step 1 (windowChanges)
        // — doesn't match. Current step matches → advance to step 1.
        let handle = AXElementHandle(AXUIElementCreateSystemWide())
        _ = walker.handle(axEvent: .focusedElementChanged(handle), currentSnapshot: nil)
        XCTAssertEqual(walker.phase, .awaitingStep(stepIndex: 1))

        let effects = walker.advanceTo(stepIndex: 0)
        XCTAssertEqual(walker.phase, .awaitingStep(stepIndex: 0))
        XCTAssertTrue(effects.contains(.emitSignal(.lessonStepCompleted)))
    }

    func testRequestFinishCurated() {
        var walker = LessonWalker(lesson: minimalLesson())
        _ = walker.didStart(currentSnapshot: nil)

        let effects = walker.requestFinish()
        XCTAssertEqual(walker.phase, .finished)
        XCTAssertTrue(effects.contains(.emitSignal(.lessonFinished)))
        XCTAssertTrue(effects.contains(.finishedWalk))
    }
}
