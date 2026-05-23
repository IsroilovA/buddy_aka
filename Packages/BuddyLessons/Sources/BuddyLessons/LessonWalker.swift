import BuddyAccessibility
import BuddySession
import BuddyUIModel
import CoreGraphics
import Foundation

/// Drives the user through a lesson's steps in response to AX/snapshot events.
///
/// Public surface is pure-input → pure-output to keep it testable: the host
/// (SessionCoordinator) feeds events in, gets `LessonEffect`s out, and
/// translates them to side-effects (point halo, send signal, request snapshot).
///
/// Supports two modes:
/// - **Curated**: `lesson.steps` is non-empty; matchers auto-advance with 2-step look-ahead.
/// - **Open-loop** (ad-hoc): `lesson.steps` is empty; advance happens only via
///   `advanceTo(stepIndex:)` / `requestFinish()`.
public struct LessonWalker: Sendable {
    public enum Phase: Sendable, Equatable {
        case awaitingStep(stepIndex: Int)
        case finished
        case exited
    }

    public let lesson: Lesson
    public private(set) var phase: Phase

    private var lastSnapshotElements: [UIElementNode] = []
    private var openLoopCounter: Int = 0

    public init(lesson: Lesson) {
        self.lesson = lesson
        self.phase = .awaitingStep(stepIndex: 0)
    }

    public var currentStepIndex: Int? {
        if case .awaitingStep(let i) = phase { return i }
        return nil
    }

    public var currentStep: LessonStep? {
        guard let i = currentStepIndex, lesson.steps.indices.contains(i) else { return nil }
        return lesson.steps[i]
    }

    public var isFinished: Bool {
        if case .finished = phase { return true }
        if case .exited = phase { return true }
        return false
    }

    // MARK: - Effects

    public enum LessonEffect: Sendable, Equatable {
        case emitSignal(BuddySignal)
        case emitEvent(BuddyRuntimeEvent)
        case pointAtMatch(stepIndex: Int)
        case clearPointing
        case requestSnapshot
        case finishedWalk
    }

    // MARK: - Lifecycle

    public mutating func didStart(currentSnapshot: UISnapshot?) -> [LessonEffect] {
        guard !lesson.isOpenLoop else { return [] }
        switch phase {
        case .awaitingStep(let i):
            return startStep(i, snapshot: currentSnapshot)
        case .finished, .exited:
            return []
        }
    }

    public mutating func observe(snapshot: UISnapshot) -> [LessonEffect] {
        defer { lastSnapshotElements = snapshot.elements }
        guard !lesson.isOpenLoop else { return [] }
        guard case .awaitingStep(let i) = phase else { return [] }

        // 2-step look-ahead: check current step and the next one.
        if let nextStep = lesson.steps[safe: i + 1],
           checkStepAdvance(step: nextStep, snapshot: snapshot) {
            return advanceToIndex(i + 2, snapshot: nil)
        }

        guard let step = lesson.steps[safe: i] else { return [] }
        if checkStepAdvance(step: step, snapshot: snapshot) {
            return advance(from: i)
        }

        var effects: [LessonEffect] = []
        if let match = step.expect?.match, !match.isEmpty {
            if MatcherEvaluator.findBest(in: snapshot, matching: match) != nil {
                effects.append(.pointAtMatch(stepIndex: i))
            }
        }
        return effects
    }

    public mutating func handle(axEvent: AXEvent, currentSnapshot: UISnapshot?) -> [LessonEffect] {
        guard !lesson.isOpenLoop else { return [] }
        guard case .awaitingStep(let i) = phase,
              let step = lesson.steps[safe: i],
              let expect = step.expect else { return [] }

        let interesting: Bool
        switch axEvent {
        case .focusedElementChanged, .focusedWindowChanged, .windowCreated:
            interesting = true
        case .valueChanged:
            interesting = isValueCondition(expect.advanceWhen) || isValueCondition(expect.alsoAdvanceWhen)
        case .layoutChanged, .elementDestroyed, .menuOpened, .menuClosed:
            interesting = false
        }
        guard interesting else { return [] }

        if isValueCondition(expect.advanceWhen) || isValueCondition(expect.alsoAdvanceWhen) {
            return [.requestSnapshot]
        }

        // 2-step look-ahead for event-based conditions too.
        if let nextStep = lesson.steps[safe: i + 1],
           let nextExpect = nextStep.expect,
           (matchesEventCondition(nextExpect.advanceWhen, axEvent: axEvent)
            || (nextExpect.alsoAdvanceWhen != nil
                && matchesEventCondition(nextExpect.alsoAdvanceWhen, axEvent: axEvent))) {
            return advanceToIndex(i + 2, snapshot: nil)
        }

        if matchesEventCondition(expect.advanceWhen, axEvent: axEvent)
            || (expect.alsoAdvanceWhen != nil
                && matchesEventCondition(expect.alsoAdvanceWhen, axEvent: axEvent)) {
            return advance(from: i)
        }

        _ = currentSnapshot
        return [.requestSnapshot]
    }

    public mutating func exit() -> [LessonEffect] {
        phase = .exited
        return [
            .clearPointing,
            .emitSignal(.lessonExited),
            .emitEvent(.lessonExited),
            .finishedWalk
        ]
    }

    // MARK: - Model-driven advance API

    public mutating func advanceTo(stepIndex: Int) -> [LessonEffect] {
        guard case .awaitingStep = phase else { return [] }
        if lesson.isOpenLoop {
            openLoopCounter = stepIndex
            phase = .awaitingStep(stepIndex: stepIndex)
            return [
                .emitSignal(.lessonStepCompleted),
                .emitEvent(.lessonStepAdvanced(
                    index: stepIndex, total: nil, instruction: "", teach: nil
                ))
            ]
        }
        guard lesson.steps.indices.contains(stepIndex) else { return [] }
        return advanceToIndex(stepIndex, snapshot: nil)
    }

    public mutating func requestFinish() -> [LessonEffect] {
        guard case .awaitingStep = phase else { return [] }
        phase = .finished
        return [
            .clearPointing,
            .emitSignal(.lessonFinished),
            .emitEvent(.lessonFinished(
                wrapup: lesson.wrapup,
                suggestedNext: lesson.suggestedNext
            )),
            .finishedWalk
        ]
    }

    // MARK: - Private

    private mutating func startStep(_ i: Int, snapshot: UISnapshot?) -> [LessonEffect] {
        guard let step = lesson.steps[safe: i] else { return [] }
        var effects: [LessonEffect] = [
            .emitSignal(.lessonStepCompleted),
            .emitEvent(.lessonStepAdvanced(
                index: i,
                total: lesson.steps.count,
                instruction: step.userInstruction,
                teach: step.teach
            ))
        ]
        if let match = step.expect?.match, !match.isEmpty,
           let snapshot,
           MatcherEvaluator.findBest(in: snapshot, matching: match) != nil {
            effects.append(.pointAtMatch(stepIndex: i))
        } else {
            effects.append(.requestSnapshot)
        }
        return effects
    }

    private mutating func advance(from i: Int) -> [LessonEffect] {
        return advanceToIndex(i + 1, snapshot: nil)
    }

    private mutating func advanceToIndex(_ target: Int, snapshot: UISnapshot?) -> [LessonEffect] {
        if target >= lesson.steps.count {
            phase = .finished
            return [
                .clearPointing,
                .emitSignal(.lessonFinished),
                .emitEvent(.lessonFinished(
                    wrapup: lesson.wrapup,
                    suggestedNext: lesson.suggestedNext
                )),
                .finishedWalk
            ]
        }
        phase = .awaitingStep(stepIndex: target)
        return startStep(target, snapshot: snapshot)
    }

    private func checkStepAdvance(step: LessonStep, snapshot: UISnapshot) -> Bool {
        guard let expect = step.expect else { return false }
        return checkAdvance(condition: expect.advanceWhen, snapshot: snapshot, valueProbe: nil)
            || (expect.alsoAdvanceWhen != nil
                && checkAdvance(condition: expect.alsoAdvanceWhen, snapshot: snapshot, valueProbe: nil))
    }

    private func isValueCondition(_ c: AdvanceCondition?) -> Bool {
        switch c {
        case .valueEquals, .valueStartsWith, .valueContains, .valueMatches: return true
        default: return false
        }
    }

    private func matchesEventCondition(_ c: AdvanceCondition?, axEvent: AXEvent) -> Bool {
        guard let c else { return false }
        switch c {
        case .focusedElementChanges:
            if case .focusedElementChanged = axEvent { return true }
            return false
        case .windowChanges:
            if case .focusedWindowChanged = axEvent { return true }
            if case .windowCreated = axEvent { return true }
            return false
        default:
            return false
        }
    }

    private func checkAdvance(
        condition: AdvanceCondition?,
        snapshot: UISnapshot?,
        valueProbe: String?
    ) -> Bool {
        guard let condition else { return false }
        switch condition {
        case .focusedElementChanges, .windowChanges, .userSaidContinue:
            return false
        case .valueEquals(let want):
            return focusedValue(snapshot) == want
        case .valueStartsWith(let prefix):
            return (focusedValue(snapshot) ?? "").hasPrefix(prefix)
        case .valueContains(let needle):
            return (focusedValue(snapshot) ?? "").range(of: needle, options: [.caseInsensitive]) != nil
        case .valueMatches(let regex):
            guard let value = focusedValue(snapshot) else { return false }
            return (try? NSRegularExpression(pattern: regex))
                .map { $0.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil }
                ?? false
        case .urlContains(let needle):
            guard let url = snapshot?.url, !url.isEmpty else { return false }
            return url.range(of: needle, options: [.caseInsensitive]) != nil
        case .elementAppears(let matcher):
            guard let snapshot else { return false }
            let now = MatcherEvaluator.findAll(in: snapshot, matching: matcher).map(\.id)
            let prevSet = Set(lastSnapshotElements.filter { MatcherEvaluator.matches($0, matcher) }.map(\.id))
            return now.contains(where: { !prevSet.contains($0) })
        case .elementDisappears(let matcher):
            guard let snapshot else { return false }
            let nowSet = Set(MatcherEvaluator.findAll(in: snapshot, matching: matcher).map(\.id))
            let prevHits = lastSnapshotElements.filter { MatcherEvaluator.matches($0, matcher) }
            return prevHits.contains(where: { !nowSet.contains($0.id) })
        }
    }

    private func focusedValue(_ snapshot: UISnapshot?) -> String? {
        snapshot?.elements.first(where: { $0.focused })?.value
    }

    public mutating func resolveMatchFrame(in snapshot: UISnapshot, stepIndex: Int) -> (elementID: String, frame: CGRect)? {
        guard let step = lesson.steps[safe: stepIndex],
              let match = step.expect?.match,
              let hit = MatcherEvaluator.findBest(in: snapshot, matching: match) else {
            return nil
        }
        return (hit.id, hit.frame.cgRect)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
