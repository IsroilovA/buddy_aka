import CoreGraphics
import BuddyUIModel
import Foundation

// Extracts a sanitized DOM projection from Safari's frontmost tab via
// `do JavaScript`. Returns a normalized UI snapshot whose frames are in AX
// screen coordinates (CSS pixel viewport rects + caller-supplied web-area frame),
// plus a SafariDOMResolver for live re-resolution of element rects.
//
// The Safari side requires:
//   - Safari -> Develop -> Developer Settings -> "Allow JavaScript from Apple Events"
//   - macOS -> Privacy & Security -> Automation: host app allowed to control Safari
//
// The host app must also declare NSAppleEventsUsageDescription in its
// Info.plist; without it macOS denies events silently.
@MainActor
public final class SafariDOMExtractor {
    public enum ExtractError: Error, Sendable {
        case notAuthorized
        case noTab
        case bridgeFailed(message: String)
        case decodingFailed(message: String)
    }

    private let bridge: AppleScriptBridge

    public init(bridge: AppleScriptBridge = AppleScriptBridge()) {
        self.bridge = bridge
    }

    /// Runs the extraction script and assembles the snapshot.
    ///
    /// - Parameter webAreaFrame: AX-coordinate frame of the Safari viewport.
    ///   Used to translate JS viewport-relative rects into screen coordinates
    ///   so the dispatched snapshot lines up with what AX returns for non-browser apps.
    /// - Parameter appBundleID: bundle id to record in the snapshot (typically
    ///   `com.apple.Safari`).
    public func extract(
        webAreaFrame: CGRect,
        appBundleID: String? = "com.apple.Safari"
    ) async throws -> (snapshot: UISnapshot, resolver: SafariDOMResolver) {
        let started = Date()

        // Force the system Automation prompt before sending the JS payload.
        // The implicit prompt on `executeAndReturnError` doesn't fire reliably
        // for LSUIElement apps; this API does. After the user makes a choice,
        // BuddyAka shows up in System Settings -> Privacy & Security -> Automation
        // and subsequent calls skip the prompt.
        let permission = bridge.requestAutomation(
            bundleID: appBundleID ?? "com.apple.Safari",
            prompt: true
        )
        switch permission {
        case .authorized:
            break
        case .denied:
            throw ExtractError.notAuthorized
        case .notRunning:
            throw ExtractError.noTab
        case .unknown:
            break
        }

        let raw: String
        do {
            raw = try bridge.evalSafariJS(DOMExtractScript.extract)
        } catch AppleScriptBridge.BridgeError.notAuthorized {
            throw ExtractError.notAuthorized
        } catch AppleScriptBridge.BridgeError.emptyResult {
            // Safari returns empty for `do JavaScript` when there is no front
            // window or the active tab is a special page (Top Sites, etc.).
            throw ExtractError.noTab
        } catch {
            throw ExtractError.bridgeFailed(message: String(describing: error))
        }

        guard let data = raw.data(using: .utf8) else {
            throw ExtractError.decodingFailed(message: "non-utf8 result")
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw ExtractError.decodingFailed(message: String(describing: error))
        }

        var elements: [UIElementNode] = []
        elements.reserveCapacity(payload.items.count)
        var paths: [String: String] = [:]
        var nodes: [String: UIElementNode] = [:]
        var initialFrames: [String: UIFrame] = [:]
        paths.reserveCapacity(payload.items.count)
        nodes.reserveCapacity(payload.items.count)
        initialFrames.reserveCapacity(payload.items.count)

        // Safari's AXWebArea is anchored to the document top, so its origin
        // slides up as the user scrolls. Reshape it once into the visible
        // viewport's stable screen rect; SafariCoordinateMapping consumes that.
        let viewportScreenFrame = Self.viewportScreenFrame(
            webAreaFrame: webAreaFrame,
            viewport: payload.viewport
        )

        for item in payload.items {
            let frame = SafariCoordinateMapping.project(
                viewportRect: CGRect(x: item.frame.x, y: item.frame.y, width: item.frame.w, height: item.frame.h),
                viewportWidth: CGFloat(payload.viewport.w),
                viewportScreenFrame: viewportScreenFrame
            )
            let role = UINormalization.domRole(tag: item.tag, role: item.role, type: item.type)
            var metadata = role.1
            if let href = UINormalization.cleanText(item.href, maxLength: 120) { metadata["href"] = href }
            if let domID = UINormalization.cleanText(item.domID, maxLength: 80) { metadata["dom_id"] = domID }
            if let name = UINormalization.cleanText(item.name, maxLength: 80) { metadata["name"] = name }
            let label = UINormalization.cleanText(item.label)
            let description = UINormalization.cleanText(item.description).flatMap { $0 == label ? nil : $0 }
            let placeholder = UINormalization.cleanText(item.placeholder, maxLength: 120)
            let sensitive = UINormalization.isSensitiveField(
                role: role.0,
                label: label,
                description: description,
                placeholder: placeholder,
                inputType: item.type,
                name: item.name,
                id: item.domID
            )
            let rawValue = UINormalization.cleanText(item.value, maxLength: 120)
            let safeValue = sensitive ? nil : Self.safeValue(rawValue, role: role.0)
            let node = UIElementNode(
                id: item.id,
                source: .dom,
                role: role.0,
                label: label,
                description: description ?? placeholder,
                value: safeValue,
                hasValue: rawValue != nil,
                enabled: item.enabled,
                focused: item.focused,
                frame: UIFrame(frame),
                metadata: metadata
            )
            elements.append(node)
            paths[item.id] = item.path
            nodes[item.id] = node
            initialFrames[item.id] = UIFrame(frame)
        }

        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        let snapshot = UISnapshot(
            app: appBundleID,
            windowTitle: payload.title,
            url: payload.url,
            elements: elements,
            stats: UISnapshotStats(
                scanned: payload.stats.scanned,
                kept: elements.count,
                truncated: payload.stats.truncated,
                elapsedMs: max(elapsedMs, payload.stats.elapsedMs)
            )
        )
        let resolver = SafariDOMResolver(
            bridge: bridge,
            paths: paths,
            nodes: nodes,
            initialFrames: initialFrames,
            viewport: payload.viewport,
            viewportScreenFrame: viewportScreenFrame
        )
        return (snapshot, resolver)
    }

    /// Translates `AXWebArea` (anchored at document top) into the visible
    /// viewport's screen rect (stable under scroll). `scrollX/Y` arrive from
    /// the JS payload in CSS pixels, so we convert them via the same width-
    /// derived `pointsPerCSSPixel` that the projector uses.
    nonisolated static func viewportScreenFrame(webAreaFrame: CGRect, viewport: Viewport) -> CGRect {
        let scale: CGFloat = viewport.w > 0 ? webAreaFrame.width / CGFloat(viewport.w) : 1
        return CGRect(
            x: webAreaFrame.minX + CGFloat(viewport.scrollX) * scale,
            y: webAreaFrame.minY + CGFloat(viewport.scrollY) * scale,
            width: webAreaFrame.width,
            height: CGFloat(viewport.h) * scale
        )
    }

    private static func safeValue(_ value: String?, role: UIElementRole) -> String? {
        guard let value else { return nil }
        switch role {
        case .checkbox, .radio, .switchControl, .combobox, .slider, .spinbutton:
            return value
        default:
            return nil
        }
    }

    // MARK: - JS payload shape

    private struct Payload: Decodable {
        let url: String?
        let title: String?
        let viewport: Viewport
        let stats: Stats
        let items: [Item]
    }

    public struct Viewport: Codable, Sendable, Equatable {
        let w: Double
        let h: Double
        let scrollX: Double
        let scrollY: Double
        let dpr: Double
        let visualOffsetX: Double
        let visualOffsetY: Double
        let visualScale: Double
    }

    private struct Stats: Decodable {
        let scanned: Int
        let kept: Int
        let elapsedMs: Int
        let truncated: Bool
    }

    private struct Item: Decodable {
        let id: String
        let tag: String
        let role: String?
        let type: String?
        let label: String
        let description: String?
        let interactive: Bool
        let focused: Bool
        let enabled: Bool
        let frame: ItemFrame
        let path: String
        let value: String?
        let placeholder: String?
        let href: String?
        let name: String?
        let domID: String?

        enum CodingKeys: String, CodingKey {
            case id, tag, role, type, label, description, interactive, focused, enabled, frame, path, value, placeholder, href, name
            case domID = "dom_id"
        }
    }

    private struct ItemFrame: Decodable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
    }
}
