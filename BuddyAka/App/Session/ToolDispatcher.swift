import AppKit
import BuddyAccessibility
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

// Side-effect a tool execution had on session state. The coordinator uses this
// to transition into `.guiding` and arm the idle-timeout. nil ⇒ no transition.
enum ToolEffect {
    case pointed(elementID: String)
    case tourStarted(steps: [TourStep], resolver: UISnapshotResolving)
    case tourStopped
    case tourResumed
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

    private var currentResolver: UISnapshotResolving?
    private var currentSnapshotPID: pid_t?

    private let decoder = JSONDecoder()
    private let log = Logger(subsystem: "dev.alisher.BuddyAka", category: "ToolDispatcher")

    init(
        overlay: OverlayState,
        permissions: PermissionsCoordinator,
        targetPID: @escaping @MainActor () -> pid_t?
    ) {
        self.extractor = AXExtractor()
        self.domExtractor = SafariDOMExtractor()
        self.overlay = overlay
        self.permissions = permissions
        self.targetPID = targetPID
    }

    func reset() {
        clearSnapshot()
        overlay.setHaloTarget(nil)
    }

    func clearSnapshot() {
        currentResolver = nil
        currentSnapshotPID = nil
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
        default:
            return ToolOutcome(response: errorResponse(call, .unknownTool), effect: nil)
        }
    }

    // MARK: - get_ui_tree

    private func handleGetUITree(_ call: ToolCall) async -> ToolResponse {
        let args = (try? decoder.decode(GetUITreeArgs.self, from: call.argsJSON))
            ?? GetUITreeArgs()
        guard let pid = targetPID() else {
            return errorResponse(call, .appNotFound)
        }

        // Route to DOM extraction for browsers where AX is sparse. Falls back
        // to AX on any DOM-side failure (no Automation grant, no tab, JS error)
        // so the user still gets *something* rather than a hard error.
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        if let bundleID, domExtractionBundles.contains(bundleID) {
            if let response = await tryDOMExtraction(call: call, pid: pid, bundleID: bundleID) {
                return response
            }
            log.notice("DOM extraction unavailable for \(bundleID, privacy: .public) — falling back to AX")
        }

        let opts = AXExtractOptions(windowOnly: args.focused_window_only ?? true)
        do {
            let (snapshot, resolver) = try await extractor.extract(
                target: .pid(pid),
                options: opts
            )
            currentResolver = resolver
            currentSnapshotPID = pid
            log.notice("get_ui_tree (AX) → \(snapshot.elements.count) elements (truncated=\(snapshot.stats.truncated))")
            return ToolResponse(
                id: call.id,
                name: call.name,
                response: AnyEncodable(snapshot)
            )
        } catch AXExtractor.Error.accessibilityNotTrusted {
            permissions.refresh()
            return errorResponse(call, .accessibilityNotTrusted)
        } catch AXExtractor.Error.appNotFound {
            return errorResponse(call, .appNotFound)
        } catch AXExtractor.Error.noFocusedWindow {
            return errorResponse(call, .noFocusedWindow)
        } catch {
            return errorResponse(call, .axExtractionFailed)
        }
    }

    // Returns nil on a recoverable DOM failure (caller should fall back to AX).
    // Returns a ToolResponse on success or on an unrecoverable error worth
    // surfacing directly (e.g. accessibility not trusted, which AX would also
    // hit).
    private func tryDOMExtraction(
        call: ToolCall,
        pid: pid_t,
        bundleID: String
    ) async -> ToolResponse? {
        // Need AXWebArea frame to translate viewport coords to screen coords.
        // If we can't get it, fall back to AX rather than ship wrong frames.
        let webAreaFrame: CGRect
        do {
            var frame = try await extractor.webAreaFrame(target: .pid(pid))
            if frame == nil {
                try? await Task.sleep(nanoseconds: 150_000_000)
                frame = try await extractor.webAreaFrame(target: .pid(pid))
            }
            guard let frame else {
                log.notice("DOM extraction: no AXWebArea reachable")
                return nil
            }
            webAreaFrame = frame
        } catch AXExtractor.Error.accessibilityNotTrusted {
            permissions.refresh()
            return errorResponse(call, .accessibilityNotTrusted)
        } catch {
            return nil
        }

        do {
            let (snapshot, resolver) = try await domExtractor.extract(
                webAreaFrame: webAreaFrame,
                appBundleID: bundleID
            )
            currentResolver = resolver
            currentSnapshotPID = pid
            log.notice("get_ui_tree (DOM) → \(snapshot.elements.count) elements, \(snapshot.stats.elapsedMs)ms")
            return ToolResponse(
                id: call.id,
                name: call.name,
                response: AnyEncodable(snapshot)
            )
        } catch SafariDOMExtractor.ExtractError.notAuthorized {
            // First DOM attempt should surface the system Automation prompt.
            // If the user denies it, keep the session usable via AX fallback.
            log.notice("DOM extraction: Automation not authorized — falling back to AX")
            return nil
        } catch SafariDOMExtractor.ExtractError.noTab {
            log.notice("DOM extraction: no Safari tab — falling back to AX")
            return nil
        } catch {
            log.error("DOM extraction failed: \(String(describing: error), privacy: .public)")
            return nil
        }
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

    private func successResponse(_ call: ToolCall) -> ToolResponse {
        ToolResponse(id: call.id, name: call.name, response: AnyEncodable(ToolSuccess()))
    }

    private func freshResolver() -> Result<UISnapshotResolving, ToolErrorCode> {
        guard let resolver = currentResolver else { return .failure(.noActiveSnapshot) }
        guard let pid = targetPID() else { return .failure(.appNotFound) }
        guard currentSnapshotPID == pid else { return .failure(.staleSnapshot) }
        return .success(resolver)
    }

    // Resolves an opaque element id to a live rect in AX screen coordinates and
    // validates that the resolver is for the currently-focused app.
    private func resolveLiveRect(forElementID id: String) -> Result<CGRect, ToolErrorCode> {
        guard let resolver = currentResolver else { return .failure(.noActiveSnapshot) }
        guard let pid = targetPID() else { return .failure(.appNotFound) }
        guard currentSnapshotPID == pid else { return .failure(.staleSnapshot) }
        guard resolver.hasElement(id) else { return .failure(.elementNotFound) }
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
