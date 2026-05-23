import AppKit
import BuddyAccessibility
import BuddyLessons
import BuddySession
import BuddyUIModel
import BuddyVoice
import Foundation
import Observation
import os

enum SessionState: Equatable {
    case idle
    case connecting
    case live
    // Buddy has pointed at an element; expecting the user to act or to time out.
    // `expectedElementID` is nil for free-form pointing; lesson walker populates it
    // from the matched step.
    case guiding(expectedElementID: String?)
    case settling
    case touring(TourPhase)
    case lesson
}

enum TourPhase: Equatable { case active, paused }

@MainActor
@Observable
final class SessionCoordinator {
    private(set) var state: SessionState = .idle
    private(set) var lastError: GeminiLiveError?
    private(set) var activeLessonID: String?

    private let overlay: OverlayState
    private let permissions: PermissionsCoordinator
    private let targetTracker: TargetApplicationTracker
    private let buddySettings: BuddySettings
    private let lessonStore: LessonStore
    private let log = Logger(subsystem: "dev.alisher.BuddyAka", category: "Session")
    @ObservationIgnored private let dispatcher: ToolDispatcher

    @ObservationIgnored private var client: GeminiLiveClient?
    @ObservationIgnored private var audio: AudioEngine?
    @ObservationIgnored private var consumerTask: Task<Void, Never>?
    @ObservationIgnored private var pcmContinuation: AsyncStream<Data>.Continuation?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var axStream: AXEventStream?
    @ObservationIgnored private var axConsumerTask: Task<Void, Never>?
    @ObservationIgnored private var workspaceConsumerTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var mouseStream: MouseClickSignalSource?
    @ObservationIgnored private var mouseConsumerTask: Task<Void, Never>?
    @ObservationIgnored private var scrollStream: ScrollSignalSource?
    @ObservationIgnored private var scrollConsumerTask: Task<Void, Never>?
    @ObservationIgnored private var scrollDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var targetVisibleAtLastCheck = true
    @ObservationIgnored private var valueDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var lastEmittedValue: String?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var guidance = GuidanceSignalController()
    @ObservationIgnored private var idleTimeoutCount = 0
    @ObservationIgnored private var guidedElementID: String?
    @ObservationIgnored private var guidedAXElement: AXElementHandle?
    private static let maxIdleTimeouts = 2
    @ObservationIgnored private var turnContext = ModelTurnContext()
    @ObservationIgnored private var tour = TourController()
    @ObservationIgnored private var tourResolver: UISnapshotResolving?
    @ObservationIgnored private var tourTickTask: Task<Void, Never>?
    @ObservationIgnored private var lessonWalker: LessonWalker?

    // Pause between tour steps. With the half-duplex gate on, this is also the
    // window in which the user can speak to interrupt — keep it generous.
    private static let tourTickDelay: Duration = .milliseconds(2500)

    private static let idleTimeout: Duration = .seconds(40)
    private static let scrollDebounce: Duration = .milliseconds(500)
    private static let valueDebounce: Duration = .milliseconds(800)

    init(
        overlay: OverlayState,
        permissions: PermissionsCoordinator,
        targetTracker: TargetApplicationTracker,
        buddySettings: BuddySettings,
        lessonStore: LessonStore
    ) {
        self.overlay = overlay
        self.permissions = permissions
        self.targetTracker = targetTracker
        self.buddySettings = buddySettings
        self.lessonStore = lessonStore
        self.dispatcher = ToolDispatcher(
            overlay: overlay,
            permissions: permissions,
            targetPID: { targetTracker.currentPID },
            lessonStore: lessonStore
        )
    }

    @ObservationIgnored private var pendingInitialLessonID: String?

    func start(initialLessonID: String? = nil) throws {
        guard case .idle = state else { return }

        permissions.refresh()
        guard permissions.allGranted else {
            throw SessionStartFailure.missingPermissions
        }

        let key: String?
        do {
            key = try GeminiAPIKey.read()
        } catch {
            log.error("keychain read failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        guard let key, !key.isEmpty else {
            throw SessionStartFailure.missingAPIKey
        }

        var stream: AXEventStream?
        if let pid = targetTracker.currentPID {
            do {
                stream = try AXEventStream(initialPid: pid)
            } catch AXEventStream.Error.accessibilityNotTrusted {
                permissions.refresh()
                throw SessionStartFailure.missingPermissions
            } catch {
                log.error("AXEventStream init failed: \(error.localizedDescription, privacy: .public)")
                throw GeminiLiveError.setupFailed(reason: "AX observer init failed: \(error.localizedDescription)")
            }
        }

        lastError = nil
        overlay.show()
        state = .connecting
        axStream = stream
        pendingInitialLessonID = initialLessonID

        let audio = AudioEngine()
        self.audio = audio
        let client = GeminiLiveClient(apiKey: key)
        self.client = client

        let (pcmStream, cont) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(64))
        self.pcmContinuation = cont

        do {
            try audio.start { chunk in
                cont.yield(chunk)
            }
        } catch let err as GeminiLiveError {
            teardownAfterError(err)
            return
        } catch {
            teardownAfterError(.audioSetupFailed(reason: error.localizedDescription))
            return
        }

        sendTask = Task { [weak self] in
            for await chunk in pcmStream {
                guard let client = self?.client else { break }
                await client.send(pcm16kMono: chunk)
            }
        }

        consumerTask = Task { [weak self] in
            await self?.consumeEvents()
        }

        if let stream {
            axConsumerTask = Task { [weak self] in
                for await event in stream.events {
                    self?.handle(axEvent: event)
                }
            }
        }

        // Global click monitor — bridges the AX gap on native SwiftUI/AppKit
        // apps (System Settings, Mail, Finder) where focusedElementChanged
        // isn't reliably emitted. Uses the existing Accessibility privilege.
        let mouse = MouseClickSignalSource()
        self.mouseStream = mouse
        mouseConsumerTask = Task { [weak self] in
            for await point in mouse.events {
                self?.handle(mouseClick: point)
            }
        }

        let scroll = ScrollSignalSource()
        self.scrollStream = scroll
        scrollConsumerTask = Task { [weak self] in
            for await _ in scroll.events {
                self?.handleScrollEvent()
            }
        }

        workspaceConsumerTask = Task { [weak self] in
            guard let changes = self?.targetTracker.targetChanges else { return }
            for await pid in changes {
                guard let self else { return }
                if case .touring = self.state {
                    self.abortTour(reason: .appChanged)
                }
                self.dispatcher.clearSnapshot()
                do {
                    if let existing = self.axStream {
                        try existing.rebind(to: pid)
                        self.log.debug("axStream rebound to pid=\(pid)")
                    } else {
                        let fresh = try AXEventStream(initialPid: pid)
                        self.axStream = fresh
                        self.axConsumerTask = Task { [weak self] in
                            for await event in fresh.events {
                                self?.handle(axEvent: event)
                            }
                        }
                        self.log.debug("axStream created on pid=\(pid)")
                    }
                } catch AXEventStream.Error.accessibilityNotTrusted {
                    // Permission revoked mid-session.
                    self.permissions.refresh()
                    self.teardownAfterError(.setupFailed(reason: String(localized: "Accessibility permission was revoked.")))
                    return
                } catch {
                    self.log.error("axStream rebind/create failed: \(error.localizedDescription, privacy: .public)")
                }

                // No lesson-side handling on app activation: the lesson walker
                // advances purely on AX/snapshot evidence per step matchers.
            }
        }

        let personaContext = PersonaContext(language: buddySettings.language)
        let sessionConfig = LiveSessionConfig(
            systemInstruction: PersonaPrompt.compose(personaContext),
            tools: BuddyTools.all,
            voice: VoiceSelection(voiceName: buddySettings.voiceName),
            language: buddySettings.language
        )

        startTask = Task { [weak self] in
            do {
                try await client.start(config: sessionConfig)
            } catch let err as GeminiLiveError {
                await MainActor.run { self?.teardownAfterError(err) }
            } catch {
                await MainActor.run {
                    self?.teardownAfterError(.setupFailed(reason: error.localizedDescription))
                }
            }
        }
    }

    func start(routing: SessionStartRouting, initialLessonID: String? = nil) {
        do {
            try start(initialLessonID: initialLessonID)
        } catch SessionStartFailure.missingPermissions {
            routing.onMissingPermissions()
        } catch SessionStartFailure.missingAPIKey {
            routing.onMissingAPIKey()
        } catch {
            recordError(.setupFailed(reason: error.localizedDescription))
        }
    }

    func stop() {
        guard state != .idle else {
            // Defensive: ensure overlay is hidden even if start() bailed early.
            overlay.hide()
            return
        }
        tearDown()
        let c = client
        client = nil
        Task { await c?.stop() }
        state = .idle
        activeLessonID = nil
    }

    private func tearDown() {
        startTask?.cancel()
        startTask = nil
        consumerTask?.cancel()
        consumerTask = nil
        audio?.stop()
        audio = nil
        pcmContinuation?.finish()
        pcmContinuation = nil
        sendTask?.cancel()
        sendTask = nil
        axConsumerTask?.cancel()
        axConsumerTask = nil
        workspaceConsumerTask?.cancel()
        workspaceConsumerTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        pendingInitialLessonID = nil
        settleTask?.cancel()
        settleTask = nil
        mouseConsumerTask?.cancel()
        mouseConsumerTask = nil
        mouseStream?.stop()
        mouseStream = nil
        scrollConsumerTask?.cancel()
        scrollConsumerTask = nil
        scrollDebounceTask?.cancel()
        scrollDebounceTask = nil
        scrollStream?.stop()
        scrollStream = nil
        targetVisibleAtLastCheck = true
        valueDebounceTask?.cancel()
        valueDebounceTask = nil
        lastEmittedValue = nil
        axStream?.stop()
        axStream = nil
        tourTickTask?.cancel()
        tourTickTask = nil
        tour.stop()
        tourResolver = nil
        lessonWalker = nil
        dispatcher.reset()
        guidance.reset()
        turnContext = ModelTurnContext()
        overlay.hide()
    }

    var isActive: Bool { state != .idle }

    func clearLastError() {
        lastError = nil
    }

    func recordError(_ error: GeminiLiveError) {
        lastError = error
    }

    // MARK: - Private

    private func consumeEvents() async {
        guard let client else { return }
        for await event in await client.events {
            await handle(event: event)
        }
    }

    private func handle(event: LiveEvent) async {
        switch event {
        case .connected:
            state = .live
            log.notice("session connected — sending session_started kickoff turn")
            emit(.sessionStarted)
            if let lessonID = pendingInitialLessonID {
                pendingInitialLessonID = nil
                if let lesson = lessonStore.lesson(id: lessonID) {
                    beginLesson(spec: .curated(lesson))
                }
            }
        case .audioChunk(let pcm):
            turnContext.phaseChanged(to: .speaking)
            audio?.play(pcm24kMono: pcm)
        case .inputTranscript, .outputTranscript:
            break
        case .interrupted:
            audio?.cancelPlayback()
            if case .touring(.active) = state {
                tourTickTask?.cancel()
                tourTickTask = nil
                state = .touring(.paused)
                log.notice("interrupted → tour paused")
            }
        case .turnComplete:
            if let payload = turnContext.drainOnTurnComplete() {
                Task { [weak self] in
                    await self?.client?.sendRealtimeText(payload)
                }
            }
            if case .guiding = state { armIdleTimer() }
            if case .lesson = state { armIdleTimer() }
            if case .touring(.active) = state { armTourTick() }
            log.debug("turn complete")
        case .toolCall(let call):
            if let response = rejectToolCallIfNeeded(call) {
                do {
                    try await client?.send(toolResponse: response)
                } catch {
                    log.error("toolResponse send failed: \(error.localizedDescription, privacy: .public)")
                }
                return
            }
            let outcome = await dispatcher.dispatch(call)
            do {
                try await client?.send(toolResponse: outcome.response)
            } catch {
                // Don't tear the session down on a single send failure —
                // receiveLoop will surface a real disconnect via .disconnected.
                log.error("toolResponse send failed: \(error.localizedDescription, privacy: .public)")
            }
            applyToolEffect(outcome.effect, call: call)
        case .toolCallCancellation(let ids):
            log.notice("Gemini toolCallCancellation ids=\(ids.joined(separator: ","), privacy: .public)")
        case .sessionResumptionUpdate(let handle, let resumable):
            if resumable, let handle, !handle.isEmpty {
                log.debug("session resumption handle stored")
                UserDefaults.standard.set(handle, forKey: "dev.alisher.BuddyAka.lastResumptionHandle")
            }
        case .goAway(let reason):
            log.notice("Gemini goAway: \(reason ?? "unknown", privacy: .public)")
        case .disconnected(let err):
            if let err {
                teardownAfterError(err)
            } else {
                // Clean stop initiated from our side; teardown already in progress.
                if state != .idle {
                    overlay.hide()
                    state = .idle
                    activeLessonID = nil
                }
            }
        }
    }

    // MARK: - AX events / guiding state

    private func handle(mouseClick point: CGPoint) {
        apply(guidance.handleMouseClick(point))
        // Lesson walker doesn't use mouse clicks directly today — its advance
        // signals come from AX + snapshot value reads. Skip.
    }

    private func handle(axEvent: AXEvent) {
        apply(guidance.handleAXEvent(axEvent))

        if case .valueChanged(let handle) = axEvent {
            handleValueChanged(handle)
        }

        if var walker = lessonWalker {
            let effects = walker.handle(axEvent: axEvent, currentSnapshot: nil)
            lessonWalker = walker
            applyLessonEffects(effects)
        }
    }

    private func handleScrollEvent() {
        guard case .guiding = state else { return }
        guard let elementID = guidedElementID else { return }

        scrollDebounceTask?.cancel()
        scrollDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.scrollDebounce)
            guard let self, !Task.isCancelled else { return }
            self.checkScrollVisibility(elementID: elementID)
        }
    }

    private func checkScrollVisibility(elementID: String) {
        guard case .guiding = state else { return }

        let isVisible: Bool
        if let axRect = dispatcher.liveFrame(for: elementID) {
            let cocoaRect = ScreenGeometry.axRectToCocoa(axRect)
            isVisible = NSScreen.screens.contains { $0.frame.intersects(cocoaRect) }
        } else {
            isVisible = false
        }

        if targetVisibleAtLastCheck && !isVisible {
            targetVisibleAtLastCheck = false
            emit(.targetScrolledOffScreen)
        } else if !targetVisibleAtLastCheck && isVisible {
            targetVisibleAtLastCheck = true
        }
    }

    private func handleValueChanged(_ handle: AXElementHandle) {
        guard case .guiding = state else { return }
        guard let guided = guidedAXElement, handle == guided else { return }

        valueDebounceTask?.cancel()
        valueDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.valueDebounce)
            guard let self, !Task.isCancelled else { return }
            self.checkValueChanged()
        }
    }

    private func checkValueChanged() {
        guard case .guiding = state else { return }
        guard let guided = guidedAXElement else { return }

        let currentValue = guided.displayValue
        guard currentValue != lastEmittedValue else { return }
        lastEmittedValue = currentValue
        emit(.targetValueChanged)
    }

    private func enterGuiding(expectedElementID: String?) {
        guard let frame = overlay.haloTargetFrame, let expectedElementID else { return }
        guidance.startGuiding(elementID: expectedElementID, frame: frame)
        state = .guiding(expectedElementID: expectedElementID)
        guidedElementID = expectedElementID
        guidedAXElement = dispatcher.axElementHandle(for: expectedElementID)
        idleTimeoutCount = 0
        targetVisibleAtLastCheck = true
        scrollDebounceTask?.cancel()
        scrollDebounceTask = nil
        valueDebounceTask?.cancel()
        valueDebounceTask = nil
        lastEmittedValue = nil
        armIdleTimer()
    }

    private func armIdleTimer() {
        guard idleTimeoutCount < Self.maxIdleTimeouts else { return }
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTimeout)
            guard let self else { return }
            guard !Task.isCancelled else { return }
            self.idleTimeoutCount += 1
            self.apply(self.guidance.handleTimeout())
        }
    }

    private func apply(_ output: GuidanceSignalOutput) {
        switch output {
        case .none:
            return
        case .scheduleSettle:
            state = .settling
            timeoutTask?.cancel()
            timeoutTask = nil
            settleTask?.cancel()
            settleTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, !Task.isCancelled else { return }
                self.apply(self.guidance.finishSettling())
            }
        case .send(let signal):
            if signal != .idleTimeout {
                timeoutTask?.cancel()
                timeoutTask = nil
                settleTask?.cancel()
                settleTask = nil
                scrollDebounceTask?.cancel()
                scrollDebounceTask = nil
                valueDebounceTask?.cancel()
                valueDebounceTask = nil
                guidedElementID = nil
                guidedAXElement = nil
                if case .lesson = state {
                    // Stay in lesson state; signal goes out the door.
                } else {
                    state = .live
                }
            }
            emit(signal)
        }
    }

    private func emit(_ signal: BuddySignal) {
        let decision = turnContext.enqueue(signal)
        switch decision {
        case .sendNow(let payload):
            log.notice("emit \(signal.rawValue, privacy: .public) → sendNow")
            sendModelText(payload)
        case .buffered:
            log.debug("emit \(signal.rawValue, privacy: .public) → buffered")
        case .dropped(let reason):
            log.notice("emit \(signal.rawValue, privacy: .public) → dropped \(reason.rawValue, privacy: .public)")
        }
    }

    private func sendModelText(_ text: String) {
        Task { [weak self] in
            await self?.client?.sendRealtimeText(text)
        }
    }

    private func rejectToolCallIfNeeded(_ call: ToolCall) -> ToolResponse? {
        guard let rejection = BuddyToolGate.rejection(for: call.name, mode: toolGateMode) else { return nil }
        log.notice("tool \(call.name, privacy: .public) rejected by session state: \(rejection.rawValue, privacy: .public)")
        return ToolErrorResponse.make(call: call, error: rejection.rawValue)
    }

    private var toolGateMode: BuddySessionMode {
        switch state {
        case .live:
            .live
        case .guiding:
            .guiding
        case .settling:
            .settling
        case .touring(.active):
            .touringActive
        case .touring(.paused):
            .touringPaused
        case .lesson:
            .lessonActive
        case .idle, .connecting:
            .other
        }
    }

    // MARK: - Lesson walker effects

    private func applyLessonEffects(_ effects: [LessonWalker.LessonEffect]) {
        guard !effects.isEmpty else { return }
        for effect in effects {
            switch effect {
            case .emitSignal(let signal):
                emit(signal)
            case .emitEvent(let event):
                sendModelText(event.envelope())
            case .pointAtMatch(let stepIndex):
                pointAtLessonStep(stepIndex: stepIndex)
            case .clearPointing:
                overlay.setHaloTarget(nil)
            case .requestSnapshot:
                break
            case .finishedWalk:
                endLesson()
            }
        }
    }

    private func pointAtLessonStep(stepIndex: Int) {
        _ = stepIndex
    }

    // MARK: - Lesson lifecycle

    private func beginLesson(spec: LessonStartSpec) {
        let lesson: Lesson
        switch spec {
        case .curated(let l):
            lesson = l
        case .adHoc(let topic):
            lesson = Lesson(
                id: "ad-hoc:\(UUID().uuidString)",
                title: topic,
                app: .bundleID(""),
                steps: []
            )
        }
        let walker = LessonWalker(lesson: lesson)
        lessonWalker = walker
        activeLessonID = lesson.id
        state = .lesson
        armIdleTimer()

        let event = BuddyRuntimeEvent.lessonStarted(
            id: lesson.id,
            title: lesson.title,
            intro: lesson.intro,
            teachingStance: lesson.teachingStance,
            steps: lesson.steps.map(\.userInstruction),
            wrapup: lesson.wrapup,
            suggestedNext: lesson.suggestedNext,
            estimatedMinutes: lesson.estimatedMinutes
        )
        sendModelText(event.envelope())

        if !lesson.isOpenLoop {
            var w = lessonWalker!
            let effects = w.didStart(currentSnapshot: nil)
            lessonWalker = w
            applyLessonEffects(effects)
        }
    }

    private func endLesson() {
        lessonWalker = nil
        activeLessonID = nil
        state = .live
        overlay.setHaloTarget(nil)
    }

    // MARK: - Tool effects

    private func applyToolEffect(_ effect: ToolEffect?, call: ToolCall) {
        guard let effect else { return }
        switch effect {
        case .pointed(let elementID):
            enterGuiding(expectedElementID: elementID)
        case .tourStarted(let steps, let resolver):
            startTour(steps: steps, resolver: resolver)
        case .tourStopped:
            endTour(emit: nil, reason: "tour stopped")
        case .tourResumed:
            resumeTour()
        case .lessonExited:
            if var walker = lessonWalker {
                let effects = walker.exit()
                lessonWalker = walker
                applyLessonEffects(effects)
            }
        case .pointingStopped:
            overlay.setHaloTarget(nil)
            if case .guiding = state {
                state = lessonWalker != nil ? .lesson : .live
            }
            timeoutTask?.cancel()
            timeoutTask = nil
            settleTask?.cancel()
            settleTask = nil
            scrollDebounceTask?.cancel()
            scrollDebounceTask = nil
            valueDebounceTask?.cancel()
            valueDebounceTask = nil
            guidedElementID = nil
            guidedAXElement = nil
            guidance.reset()
        case .lessonStartRequested(let spec):
            beginLesson(spec: spec)
        case .lessonStepAdvanceRequested(let target):
            guard var walker = lessonWalker else { break }
            let effects: [LessonWalker.LessonEffect]
            switch target {
            case .finish:
                effects = walker.requestFinish()
            case .step(let i):
                effects = walker.advanceTo(stepIndex: i)
            case .nextStep:
                let next = (walker.currentStepIndex ?? 0) + 1
                effects = walker.advanceTo(stepIndex: next)
            }
            lessonWalker = walker
            applyLessonEffects(effects)
        }
        _ = call
    }

    private func startTour(steps: [TourStep], resolver: UISnapshotResolving) {
        guidance.reset()
        timeoutTask?.cancel()
        timeoutTask = nil
        settleTask?.cancel()
        settleTask = nil

        tourResolver = resolver
        if case .started = tour.start(steps: steps) {
            state = .touring(.active)
            log.notice("tour started: \(steps.count) steps")
        } else {
            tourResolver = nil
        }
    }

    private func resumeTour() {
        guard case .touring(.paused) = state else { return }
        state = .touring(.active)
        applyTick(tour.tick())
    }

    private func armTourTick() {
        tourTickTask?.cancel()
        tourTickTask = Task { [weak self] in
            try? await Task.sleep(for: Self.tourTickDelay)
            guard let self, !Task.isCancelled else { return }
            self.applyTick(self.tour.tick())
        }
    }

    private func applyTick(_ result: TourController.TickResult) {
        switch result {
        case .idle:
            return
        case .complete:
            endTour(emit: BuddyRuntimeEvent.tourComplete.envelope(), reason: "tour complete")
        case .step(let index, let total, let step):
            guard let resolver = tourResolver,
                  let axRect = resolver.liveFrame(for: step.elementID) else {
                endTour(
                    emit: BuddyRuntimeEvent.tourAborted(reason: .elementLost).envelope(),
                    reason: "tour aborted: element_lost"
                )
                return
            }
            let cocoa = ScreenGeometry.axRectToCocoa(axRect)
            overlay.pointAt(cocoa)
            sendModelText(BuddyRuntimeEvent.tourStep(index: index, total: total, step: step).envelope())
            log.notice("tour step \(index + 1)/\(total) → \(step.elementID, privacy: .public)")
        }
    }

    private func abortTour(reason: TourAbortReason) {
        endTour(
            emit: BuddyRuntimeEvent.tourAborted(reason: reason).envelope(),
            reason: "tour aborted: \(reason.rawValue)"
        )
    }

    private func endTour(emit payload: String?, reason: String) {
        tourTickTask?.cancel()
        tourTickTask = nil
        tour.stop()
        tourResolver = nil
        overlay.setHaloTarget(nil)
        state = lessonWalker != nil ? .lesson : .live
        if let payload {
            sendModelText(payload)
        }
        log.notice("\(reason, privacy: .public)")
    }

    private func teardownAfterError(_ error: GeminiLiveError) {
        tearDown()
        let c = client
        client = nil
        Task { await c?.stop() }
        state = .idle
        activeLessonID = nil
        if case .keyRejected = error {
            try? GeminiAPIKey.clear()
        }
        lastError = error
    }
}

