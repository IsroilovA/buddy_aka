import AppKit
import BuddyAccessibility
import BuddyLessons
import BuddySafariDOM
import BuddySession
import BuddyUIModel
import BuddyVoice
import CoreGraphics
import Foundation
import os

// Wire-contract error codes echoed in the persona prompt — keep names in sync
// with the literals embedded in `PersonaPrompt.v1` when adding new ones.
enum ToolErrorCode: String, Error {
    case unknownTool = "unknown_tool"
    case invalidArgs = "invalid_args"
    case noActiveSnapshot = "no_active_snapshot"
    case elementNotFound = "element_not_found"
    case staleSnapshot = "stale_snapshot"
    case accessibilityNotTrusted = "accessibility_not_trusted"
    case appNotFound = "app_not_found"
    case noFocusedWindow = "no_focused_window"
    case axExtractionFailed = "ax_extraction_failed"
    case elementOffscreen = "element_offscreen"
    case allElementsUnresolved = "all_elements_unresolved"
    case lessonNotFound = "lesson_not_found"
    case lessonAlreadyActive = "lesson_already_active"
    case noActiveLesson = "no_active_lesson"
    case stepOutOfRange = "step_out_of_range"
    case missingLessonIdOrTopic = "missing_lesson_id_or_topic"
}

// Bundle IDs whose frontmost window we extract via DOM (AppleScript +
// JavaScript) instead of AX. AX in modern WebKit/Chromium pages is sparse and
// often unlabeled; DOM gives us labelled, near-complete coverage in ~70ms.
// Add Chrome / Brave / Arc when those bridges land.
private let domExtractionBundles: Set<String> = [
    "com.apple.Safari",
]

// Empty-payload success body shared by the simple tour tools.
struct ToolSuccess: Encodable { let success = true }

enum LessonStartSpec {
    case curated(BuddyLessons.Lesson)
    case adHoc(topic: String)
}

enum AdvanceTarget {
    case nextStep
    case step(Int)
    case finish
}

// Side-effect a tool execution had on session state. The coordinator uses this
// to transition into `.guiding` and arm the idle-timeout. nil ⇒ no transition.
enum ToolEffect {
    case pointed(elementID: String)
    case tourStarted(steps: [TourStep], resolver: UISnapshotResolving)
    case tourStopped
    case tourResumed
    case lessonExited
    case pointingStopped
    case lessonStartRequested(spec: LessonStartSpec)
    case lessonStepAdvanceRequested(target: AdvanceTarget)
}

struct ToolOutcome {
    let response: ToolResponse
    let effect: ToolEffect?
}

@MainActor
final class ToolDispatcher {
    private let extractor: AXExtractor
    private let domExtractor: SafariDOMExtractor
    private let overlay: OverlayState
    private let permissions: PermissionsCoordinator
    private let targetPID: @MainActor () -> pid_t?
    private let lessonStore: LessonStore

    private var currentResolver: UISnapshotResolving?
    private var currentSnapshotPID: pid_t?

    private let decoder = JSONDecoder()
    private let log = Logger(subsystem: "dev.alisher.BuddyAka", category: "ToolDispatcher")

    init(
        overlay: OverlayState,
        permissions: PermissionsCoordinator,
        targetPID: @escaping @MainActor () -> pid_t?,
        lessonStore: LessonStore
    ) {
        self.extractor = AXExtractor()
        self.domExtractor = SafariDOMExtractor()
        self.overlay = overlay
        self.permissions = permissions
        self.targetPID = targetPID
        self.lessonStore = lessonStore
    }

    func reset() {
        clearSnapshot()
        overlay.setHaloTarget(nil)
    }

    func clearSnapshot() {
        currentResolver = nil
        currentSnapshotPID = nil
    }

    /// Re-reads the live frame for a snapshot element ID. Returns nil if the
    /// resolver is stale, the element is unknown, or AX can no longer locate it.
    func liveFrame(for elementID: String) -> CGRect? {
        guard let resolver = currentResolver else { return nil }
        return resolver.liveFrame(for: elementID)
    }

    /// Returns the underlying AXUIElement handle for an element ID, if the
    /// resolver is AX-backed. DOM-backed elements return nil.
    func axElementHandle(for elementID: String) -> AXElementHandle? {
        guard let resolver = currentResolver else { return nil }
        if let composite = resolver as? CompositeSnapshotResolver {
            return composite.axElement(for: elementID).map(AXElementHandle.init)
        }
        if let ax = resolver as? AXSnapshotResolver {
            return ax.element(for: elementID).map(AXElementHandle.init)
        }
        return nil
    }

    // Always produces an outcome — Gemini 3.1 Flash Live blocks until the
    // toolResponse arrives, so we never throw out and never skip a reply.
    func dispatch(_ call: ToolCall) async -> ToolOutcome {
        let args = String(data: call.argsJSON, encoding: .utf8) ?? "<non-utf8>"
        log.notice("→ \(call.name, privacy: .public) id=\(call.id, privacy: .public) args=\(args, privacy: .public)")

        switch call.name {
        case "get_ui_tree":
            return ToolOutcome(response: await handleGetUITree(call), effect: nil)
        case "point_to_element":
            return await handlePointToElement(call)
        case "start_tour":
            return handleStartTour(call)
        case "stop_tour":
            return handleStopTour(call)
        case "resume_tour":
            return handleResumeTour(call)
        case "exit_lesson":
            return handleExitLesson(call)
        case "stop_pointing":
            return handleStopPointing(call)
        case "list_lessons":
            return handleListLessons(call)
        case "start_lesson":
            return handleStartLesson(call)
        case "advance_lesson_step":
            return handleAdvanceLessonStep(call)
        default:
            return ToolOutcome(response: errorResponse(call, .unknownTool), effect: nil)
        }
    }

    // MARK: - get_ui_tree

    private func handleGetUITree(_ call: ToolCall) async -> ToolResponse {
        let args = (try? decoder.decode(GetUITreeArgs.self, from: call.argsJSON))
            ?? GetUITreeArgs()

        let pid = targetPID()
        let bundleID = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }

        // Build the window/page snapshot via DOM (browsers) or AX (everything else).
        // When no app is focused, we skip this step — menu bar + Dock still come through.
        var windowSnapshot: UISnapshot?
        var windowResolver: (any UISnapshotResolving)?

        if let pid {
            if let bundleID, domExtractionBundles.contains(bundleID) {
                if let (snap, resolver) = await tryDOMExtractionFragment(call: call, pid: pid, bundleID: bundleID) {
                    windowSnapshot = snap
                    windowResolver = resolver
                } else {
                    log.notice("DOM extraction unavailable for \(bundleID ?? "?", privacy: .public) — falling back to AX")
                }
            }
            if windowSnapshot == nil {
                let opts = AXExtractOptions(windowOnly: args.focused_window_only ?? true)
                do {
                    let (snap, resolver) = try await extractor.extract(target: .pid(pid), options: opts)
                    windowSnapshot = snap
                    windowResolver = resolver
                } catch AXExtractor.Error.accessibilityNotTrusted {
                    permissions.refresh()
                    return errorResponse(call, .accessibilityNotTrusted)
                } catch AXExtractor.Error.appNotFound, AXExtractor.Error.noFocusedWindow {
                    // Fall through with no window snapshot. Persona handles via NO APP FOCUSED.
                    windowSnapshot = nil
                } catch {
                    log.error("AX extraction failed: \(String(describing: error), privacy: .public)")
                    windowSnapshot = nil
                }
            }
        }

        // Menu bar (uses frontmost app's pid; falls back to the workspace's
        // current frontmost if no PID is being tracked yet).
        var menuBarElements: [UIElementNode] = []
        var menuBarResolver: (any UISnapshotResolving)?
        let menuBarPID = pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let menuBarPID {
            if let (els, resolver) = try? await extractor.extractMenuBar(forPID: menuBarPID) {
                menuBarElements = els
                menuBarResolver = resolver
            }
        }

        // Dock (always queried — separate process).
        var dockElements: [UIElementNode] = []
        var dockResolver: (any UISnapshotResolving)?
        if let (els, resolver) = try? await extractor.extractDock() {
            dockElements = els
            dockResolver = resolver
        }

        // Merge into one snapshot.
        var combinedElements: [UIElementNode] = []
        if let windowSnapshot { combinedElements.append(contentsOf: windowSnapshot.elements) }
        combinedElements.append(contentsOf: menuBarElements)
        combinedElements.append(contentsOf: dockElements)

        let mergedSnapshot = UISnapshot(
            app: windowSnapshot?.app ?? bundleID,
            windowTitle: windowSnapshot?.windowTitle,
            url: windowSnapshot?.url,
            elements: combinedElements,
            stats: UISnapshotStats(
                scanned: (windowSnapshot?.stats.scanned ?? 0) + menuBarElements.count + dockElements.count,
                kept: combinedElements.count,
                truncated: windowSnapshot?.stats.truncated ?? false,
                elapsedMs: windowSnapshot?.stats.elapsedMs ?? 0
            )
        )

        let composite = CompositeSnapshotResolver([windowResolver, menuBarResolver, dockResolver].compactMap { $0 })
        currentResolver = composite
        currentSnapshotPID = pid
        log.notice("get_ui_tree → \(mergedSnapshot.elements.count) elements (window=\(windowSnapshot?.elements.count ?? 0) menuBar=\(menuBarElements.count) dock=\(dockElements.count))")
        return ToolResponse(
            id: call.id,
            name: call.name,
            response: AnyEncodable(mergedSnapshot)
        )
    }

    private func tryDOMExtractionFragment(
        call: ToolCall,
        pid: pid_t,
        bundleID: String
    ) async -> (UISnapshot, any UISnapshotResolving)? {
        let webAreaFrame: CGRect
        do {
            var frame = try await extractor.webAreaFrame(target: .pid(pid))
            if frame == nil {
                try? await Task.sleep(nanoseconds: 150_000_000)
                frame = try await extractor.webAreaFrame(target: .pid(pid))
            }
            guard let frame else { return nil }
            webAreaFrame = frame
        } catch {
            return nil
        }
        do {
            let (snapshot, resolver) = try await domExtractor.extract(
                webAreaFrame: webAreaFrame,
                appBundleID: bundleID
            )
            return (snapshot, resolver)
        } catch SafariDOMExtractor.ExtractError.notAuthorized, SafariDOMExtractor.ExtractError.noTab {
            return nil
        } catch {
            log.error("DOM extraction failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        _ = call
    }

    // MARK: - point_to_element

    private func handlePointToElement(_ call: ToolCall) async -> ToolOutcome {
        guard let args = try? decoder.decode(PointToElementArgs.self,
                                             from: call.argsJSON) else {
            return ToolOutcome(response: errorResponse(call, .invalidArgs), effect: nil)
        }
        let axRect: CGRect
        switch resolveLiveRect(forElementID: args.element_id) {
        case .success(let r): axRect = r
        case .failure(let code): return ToolOutcome(response: errorResponse(call, code), effect: nil)
        }

        let cocoaRect = ScreenGeometry.axRectToCocoa(axRect)

        if let info = offscreenInfo(of: cocoaRect) {
            overlay.setHaloTarget(nil)
            overlay.show()
            overlay.move(to: info.nudgePoint)
            log.notice("point_to_element \(args.element_id, privacy: .public) → offscreen \(info.direction.rawValue, privacy: .public)")
            return ToolOutcome(
                response: errorResponse(call, .elementOffscreen, direction: info.direction.rawValue),
                effect: nil
            )
        }

        overlay.pointAt(cocoaRect)

        log.notice("point_to_element \(args.element_id, privacy: .public) → (\(Int(cocoaRect.midX)),\(Int(cocoaRect.midY))) \(Int(cocoaRect.width))x\(Int(cocoaRect.height))")

        struct OK: Encodable {
            let success = true
            let frame: UIFrame
        }
        let response = ToolResponse(
            id: call.id,
            name: call.name,
            response: AnyEncodable(OK(frame: UIFrame(cocoaRect)))
        )
        return ToolOutcome(response: response, effect: .pointed(elementID: args.element_id))
    }

    // MARK: - start_tour / stop_tour / resume_tour

    private func handleStartTour(_ call: ToolCall) -> ToolOutcome {
        guard let args = try? decoder.decode(StartTourArgs.self, from: call.argsJSON) else {
            return ToolOutcome(response: errorResponse(call, .invalidArgs), effect: nil)
        }
        let resolver: UISnapshotResolving
        switch freshResolver() {
        case .success(let r): resolver = r
        case .failure(let code): return ToolOutcome(response: errorResponse(call, code), effect: nil)
        }

        var steps: [TourStep] = []
        var initialCocoaFrame: CGRect?
        for id in args.element_ids.prefix(TourController.maxSteps) {
            guard let node = resolver.node(for: id) else { continue }
            guard let axRect = resolver.liveFrame(for: id) else { continue }
            let label = node.label ?? node.description ?? node.value ?? ""
            let step = TourStep(elementID: id, label: label, role: node.role.rawValue)
            steps.append(step)
            if initialCocoaFrame == nil {
                initialCocoaFrame = ScreenGeometry.axRectToCocoa(axRect)
            }
        }

        guard let firstFrame = initialCocoaFrame, let first = steps.first else {
            return ToolOutcome(response: errorResponse(call, .allElementsUnresolved), effect: nil)
        }

        overlay.pointAt(firstFrame)

        log.notice("start_tour → \(steps.count) elements")

        struct CurrentStep: Encodable {
            let id: String
            let label: String
            let role: String
            let frame: UIFrame
        }
        struct OK: Encodable {
            let success = true
            let total: Int
            let current_index: Int
            let current: CurrentStep
        }
        let payload = OK(
            total: steps.count,
            current_index: 0,
            current: CurrentStep(
                id: first.elementID,
                label: first.label,
                role: first.role,
                frame: UIFrame(firstFrame)
            )
        )
        let response = ToolResponse(id: call.id, name: call.name, response: AnyEncodable(payload))
        return ToolOutcome(
            response: response,
            effect: .tourStarted(steps: steps, resolver: resolver)
        )
    }

    private func handleStopTour(_ call: ToolCall) -> ToolOutcome {
        log.notice("stop_tour")
        return ToolOutcome(response: successResponse(call), effect: .tourStopped)
    }

    private func handleResumeTour(_ call: ToolCall) -> ToolOutcome {
        log.notice("resume_tour")
        return ToolOutcome(response: successResponse(call), effect: .tourResumed)
    }

    private func handleExitLesson(_ call: ToolCall) -> ToolOutcome {
        log.notice("exit_lesson")
        return ToolOutcome(response: successResponse(call), effect: .lessonExited)
    }

    private func handleStopPointing(_ call: ToolCall) -> ToolOutcome {
        log.notice("stop_pointing")
        return ToolOutcome(response: successResponse(call), effect: .pointingStopped)
    }

    // MARK: - list_lessons / start_lesson / advance_lesson_step

    private func handleListLessons(_ call: ToolCall) -> ToolOutcome {
        struct Entry: Encodable {
            let id: String
            let title: String
            let app: String
            let estimated_minutes: Int?
        }
        let entries = lessonStore.lessons.map { lesson in
            let appDesc: String
            switch lesson.app {
            case .bundleID(let id): appDesc = id
            case .urlMatch(let url): appDesc = url
            }
            return Entry(id: lesson.id, title: lesson.title, app: appDesc, estimated_minutes: lesson.estimatedMinutes)
        }
        log.notice("list_lessons → \(entries.count) lessons")
        return ToolOutcome(
            response: ToolResponse(id: call.id, name: call.name, response: AnyEncodable(entries)),
            effect: nil
        )
    }

    private func handleStartLesson(_ call: ToolCall) -> ToolOutcome {
        guard let args = try? decoder.decode(StartLessonArgs.self, from: call.argsJSON) else {
            return ToolOutcome(response: errorResponse(call, .invalidArgs), effect: nil)
        }
        if args.lesson_id != nil && args.topic != nil {
            return ToolOutcome(response: errorResponse(call, .invalidArgs), effect: nil)
        }
        if let lessonID = args.lesson_id {
            guard let lesson = lessonStore.lesson(id: lessonID) else {
                return ToolOutcome(response: errorResponse(call, .lessonNotFound), effect: nil)
            }
            log.notice("start_lesson → curated \(lessonID, privacy: .public)")
            return ToolOutcome(
                response: successResponse(call),
                effect: .lessonStartRequested(spec: .curated(lesson))
            )
        }
        if let topic = args.topic, !topic.isEmpty {
            log.notice("start_lesson → ad-hoc \(topic, privacy: .public)")
            return ToolOutcome(
                response: successResponse(call),
                effect: .lessonStartRequested(spec: .adHoc(topic: topic))
            )
        }
        return ToolOutcome(response: errorResponse(call, .missingLessonIdOrTopic), effect: nil)
    }

    private func handleAdvanceLessonStep(_ call: ToolCall) -> ToolOutcome {
        let args = (try? decoder.decode(AdvanceLessonStepArgs.self, from: call.argsJSON))
            ?? AdvanceLessonStepArgs(to_step: nil, finish: nil)
        if args.finish == true {
            log.notice("advance_lesson_step → finish")
            return ToolOutcome(
                response: successResponse(call),
                effect: .lessonStepAdvanceRequested(target: .finish)
            )
        }
        if let step = args.to_step {
            log.notice("advance_lesson_step → step \(step)")
            return ToolOutcome(
                response: successResponse(call),
                effect: .lessonStepAdvanceRequested(target: .step(step))
            )
        }
        log.notice("advance_lesson_step → next")
        return ToolOutcome(
            response: successResponse(call),
            effect: .lessonStepAdvanceRequested(target: .nextStep)
        )
    }

    private func successResponse(_ call: ToolCall) -> ToolResponse {
        ToolResponse(id: call.id, name: call.name, response: AnyEncodable(ToolSuccess()))
    }

    private func freshResolver() -> Result<UISnapshotResolving, ToolErrorCode> {
        guard let resolver = currentResolver else { return .failure(.noActiveSnapshot) }
        // Tour mode is window-bound; require the same app to be in focus.
        guard let pid = targetPID() else { return .failure(.appNotFound) }
        guard currentSnapshotPID == pid else { return .failure(.staleSnapshot) }
        return .success(resolver)
    }

    // Resolves an opaque element id to a live rect in AX screen coordinates.
    // Menu bar (mb_) and Dock (dk_) IDs are valid regardless of the currently
    // focused app — those elements live in separate processes that don't go
    // stale on app switch. App-window IDs (aw_, or DOM extractor IDs) still
    // require the originating app to be in focus.
    private func resolveLiveRect(forElementID id: String) -> Result<CGRect, ToolErrorCode> {
        guard let resolver = currentResolver else { return .failure(.noActiveSnapshot) }
        guard resolver.hasElement(id) else { return .failure(.elementNotFound) }

        let isChromeID = id.hasPrefix("mb_") || id.hasPrefix("dk_")
        if !isChromeID {
            guard let pid = targetPID() else { return .failure(.appNotFound) }
            guard currentSnapshotPID == pid else { return .failure(.staleSnapshot) }
        }
        guard let rect = resolver.liveFrame(for: id) else {
            return .failure(.staleSnapshot)
        }
        return .success(rect)
    }

    private enum OffscreenDirection: String {
        case above, below, left, right
    }

    private struct OffscreenInfo {
        let direction: OffscreenDirection
        let nudgePoint: CGPoint
    }

    private func offscreenInfo(of rect: CGRect) -> OffscreenInfo? {
        if NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) { return nil }

        let cursor = NSEvent.mouseLocation
        let visible = ScreenGeometry.screen(containing: cursor).visibleFrame

        let dx = rect.midX - visible.midX
        let dy = rect.midY - visible.midY
        let direction: OffscreenDirection
        if abs(dx) >= abs(dy) {
            direction = dx >= 0 ? .right : .left
        } else {
            direction = dy >= 0 ? .above : .below
        }

        let margin: CGFloat = 24
        let nudge: CGPoint
        switch direction {
        case .above: nudge = CGPoint(x: visible.midX, y: visible.maxY - margin)
        case .below: nudge = CGPoint(x: visible.midX, y: visible.minY + margin)
        case .left:  nudge = CGPoint(x: visible.minX + margin, y: visible.midY)
        case .right: nudge = CGPoint(x: visible.maxX - margin, y: visible.midY)
        }
        return OffscreenInfo(direction: direction, nudgePoint: nudge)
    }

    private func errorResponse(_ call: ToolCall, _ code: ToolErrorCode, direction: String? = nil) -> ToolResponse {
        log.notice("tool \(call.name, privacy: .public) → \(code.rawValue, privacy: .public)")
        return ToolErrorResponse.make(call: call, error: code.rawValue, direction: direction)
    }
}

enum ToolErrorResponse {
    private struct Body: Encodable {
        let success = false
        let error: String
        let direction: String?
    }

    static func make(call: ToolCall, error: String, direction: String? = nil) -> ToolResponse {
        ToolResponse(
            id: call.id,
            name: call.name,
            response: AnyEncodable(Body(error: error, direction: direction))
        )
    }
}
