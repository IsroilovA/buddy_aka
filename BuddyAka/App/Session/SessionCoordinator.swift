import AppKit
import BuddyAccessibility
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
    // `expectedElementID` is nil in Step 6 (any focus/window change advances).
    // Step 7's curated-flow walker will populate it from the matched flow step.
    case guiding(expectedElementID: String?)
    case settling
    case touring(TourPhase)
}

enum TourPhase: Equatable { case active, paused }

@MainActor
@Observable
final class SessionCoordinator {
    private(set) var state: SessionState = .idle
    private(set) var lastError: GeminiLiveError?

    private let overlay: OverlayState
    private let permissions: PermissionsCoordinator
    private let targetTracker: TargetApplicationTracker
    private let buddySettings: BuddySettings
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
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var guidance = GuidanceSignalController()
    @ObservationIgnored private var turnContext = ModelTurnContext()
    @ObservationIgnored private var tour = TourController()
    @ObservationIgnored private var tourResolver: UISnapshotResolving?
    @ObservationIgnored private var tourTickTask: Task<Void, Never>?

    // Pause between tour steps. With the half-duplex gate on, this is also the
    // window in which the user can speak to interrupt — keep it generous.
    private static let tourTickDelay: Duration = .milliseconds(2500)

    // 25s gives the user time to actually read + act. The 5s placeholder we
    // started with had the persona re-narrating before users finished hearing
    // the first narration, which felt nagging.
    private static let idleTimeout: Duration = .seconds(25)

    init(
        overlay: OverlayState,
        permissions: PermissionsCoordinator,
        targetTracker: TargetApplicationTracker,
        buddySettings: BuddySettings
    ) {
        self.overlay = overlay
        self.permissions = permissions
        self.targetTracker = targetTracker
        self.buddySettings = buddySettings
        self.dispatcher = ToolDispatcher(
            overlay: overlay,
            permissions: permissions,
            targetPID: { targetTracker.currentPID }
        )
    }

    func start() throws {
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

        // Construct the AX event stream up-front so its permission probe runs
        // before any state mutation. If it fails, no cleanup needed.
        guard let pid = targetTracker.currentPID else {
            throw GeminiLiveError.setupFailed(reason: String(localized: "Bring the app you want help with to the front, then start again."))
        }
        let stream: AXEventStream
        do {
            stream = try AXEventStream(initialPid: pid)
        } catch AXEventStream.Error.accessibilityNotTrusted {
            permissions.refresh()
            throw SessionStartFailure.missingPermissions
        } catch {
            log.error("AXEventStream init failed: \(error.localizedDescription, privacy: .public)")
            throw GeminiLiveError.setupFailed(reason: "AX observer init failed: \(error.localizedDescription)")
        }

        lastError = nil
        overlay.show()
        state = .connecting
        axStream = stream

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

        axConsumerTask = Task { [weak self] in
            guard let events = self?.axStream?.events else { return }
            for await event in events {
                self?.handle(axEvent: event)
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

        workspaceConsumerTask = Task { [weak self] in
            guard let changes = self?.targetTracker.targetChanges else { return }
            for await pid in changes {
                guard let self else { return }
                if case .touring = self.state {
                    self.abortTour(reason: .appChanged)
                }
                self.dispatcher.clearSnapshot()
                do {
                    try self.axStream?.rebind(to: pid)
                    self.log.debug("axStream rebound to pid=\(pid)")
                } catch AXEventStream.Error.accessibilityNotTrusted {
                    // Permission revoked mid-session.
                    self.permissions.refresh()
                    self.teardownAfterError(.setupFailed(reason: String(localized: "Accessibility permission was revoked.")))
                    return
                } catch {
                    self.log.error("axStream rebind failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        let sessionConfig = LiveSessionConfig(
            systemInstruction: PersonaPrompt.v1(language: buddySettings.language),
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

    func start(routing: SessionStartRouting) {
        do {
            try start()
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
        settleTask?.cancel()
        settleTask = nil
        mouseConsumerTask?.cancel()
        mouseConsumerTask = nil
        mouseStream?.stop()
        mouseStream = nil
        axStream?.stop()
        axStream = nil
        tourTickTask?.cancel()
        tourTickTask = nil
        tour.stop()
        tourResolver = nil
        dispatcher.reset()
        guidance.reset()
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
            // Kick the model with a synthetic "session started" turn so it
            // introduces itself instead of sitting silent waiting for user
            // speech. `clientContent` with `turnComplete: true` tells Live to
            // treat this as a complete app-generated user turn.
            log.notice("session connected — sending session_started kickoff turn")
            emit(.sessionStarted)
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
                    await self?.client?.sendClientContentTurn(text: payload)
                }
            }
            if case .guiding = state { armIdleTimer() }
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
            applyToolEffect(outcome.effect)
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
                }
            }
        }
    }

    // MARK: - AX events / guiding state

    private func handle(mouseClick point: CGPoint) {
        apply(guidance.handleMouseClick(point))
    }

    private func handle(axEvent: AXEvent) {
        apply(guidance.handleAXEvent(axEvent))
    }

    private func enterGuiding(expectedElementID: String?) {
        guard let frame = overlay.haloTargetFrame, let expectedElementID else { return }
        guidance.startGuiding(elementID: expectedElementID, frame: frame)
        state = .guiding(expectedElementID: expectedElementID)
        armIdleTimer()
    }

    private func armIdleTimer() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTimeout)
            guard let self else { return }
            guard !Task.isCancelled else { return }
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
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, !Task.isCancelled else { return }
                self.apply(self.guidance.finishSettling())
            }
        case .send(let signal):
            if signal != .idleTimeout {
                timeoutTask?.cancel()
                timeoutTask = nil
                settleTask?.cancel()
                settleTask = nil
                state = .live
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
            await self?.client?.sendClientContentTurn(text: text)
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
        case .idle, .connecting:
            .other
        }
    }

    // MARK: - Tour mode

    private func applyToolEffect(_ effect: ToolEffect?) {
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
        }
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
        state = .live
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
        if case .keyRejected = error {
            try? GeminiAPIKey.clear()
        }
        lastError = error
    }
}
