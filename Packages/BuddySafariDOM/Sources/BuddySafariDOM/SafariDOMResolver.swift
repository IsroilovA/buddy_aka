import CoreGraphics
import BuddyUIModel
import Foundation

// Owns the id -> CSS-path map produced by SafariDOMExtractor. To resolve a live
// rect we re-run a JS query in Safari (via AppleScriptBridge), so the result
// reflects the page's CURRENT scroll position and layout - robust against
// users scrolling between extraction and pointing.
//
@MainActor
public final class SafariDOMResolver: @MainActor UISnapshotResolving {
    public struct ViewportRect: Sendable, Equatable {
        public var x: CGFloat
        public var y: CGFloat
        public var w: CGFloat
        public var h: CGFloat
        public var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    }

    private let bridge: AppleScriptBridge
    private let paths: [String: String]
    private let nodes: [String: UIElementNode]
    private let initialFrames: [String: UIFrame]
    private let viewport: SafariDOMExtractor.Viewport
    private let viewportScreenFrame: CGRect

    public init(
        bridge: AppleScriptBridge,
        paths: [String: String],
        nodes: [String: UIElementNode],
        initialFrames: [String: UIFrame],
        viewport: SafariDOMExtractor.Viewport,
        viewportScreenFrame: CGRect
    ) {
        self.bridge = bridge
        self.paths = paths
        self.nodes = nodes
        self.initialFrames = initialFrames
        self.viewport = viewport
        self.viewportScreenFrame = viewportScreenFrame
    }

    public var ids: [String] { Array(paths.keys) }

    /// Returns true if the id was present in the snapshot.
    public func hasElement(_ id: String) -> Bool { paths[id] != nil }
    public func node(for id: String) -> UIElementNode? { nodes[id] }

    /// Re-queries Safari for the element's current viewport rect. Returns nil
    /// when the element no longer exists (navigation, conditional render...) or
    /// when the AppleScript bridge fails. This is read-only: pointing never
    /// scrolls or mutates the page.
    public func liveViewportRect(for id: String) -> ViewportRect? {
        guard let path = paths[id] else { return nil }
        let js = DOMExtractScript.resolveScript(path: path)
        let raw: String
        do {
            raw = try bridge.evalSafariJS(js)
        } catch {
            return nil
        }
        guard raw != "null", let data = raw.data(using: .utf8) else { return nil }
        do {
            let r = try JSONDecoder().decode(ResolverPayload.self, from: data)
            return ViewportRect(x: CGFloat(r.x), y: CGFloat(r.y), w: CGFloat(r.w), h: CGFloat(r.h))
        } catch {
            return nil
        }
    }

    /// Convenience: live rect in AX screen coordinates (origin at top-left of
    /// the primary display, Y growing down). Returns nil on the same failure
    /// conditions as `liveViewportRect`.
    public func liveAXRect(for id: String) -> CGRect? {
        guard let vp = liveViewportRect(for: id) else { return nil }
        return SafariCoordinateMapping.project(
            viewportRect: vp.cgRect,
            viewportWidth: CGFloat(viewport.w),
            viewportScreenFrame: viewportScreenFrame
        )
    }

    public func liveFrame(for id: String) -> CGRect? {
        liveAXRect(for: id)
    }

    /// Last-known viewport rect from extraction time. Cheap (no AppleScript
    /// roundtrip) but stale if the user scrolled or the layout changed.
    public func cachedFrame(for id: String) -> UIFrame? { initialFrames[id] }

    private struct ResolverPayload: Decodable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
    }
}
