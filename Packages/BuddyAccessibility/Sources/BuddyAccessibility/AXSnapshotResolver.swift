import ApplicationServices
import BuddyUIModel
import Foundation

// Maps snapshot element IDs back to the live AXUIElement refs they were generated from.
// Created on the extractor actor, then read-only — safe to hand to other actors as @unchecked Sendable.
public final class AXSnapshotResolver: @unchecked Sendable, UISnapshotResolving {
    private let elements: [String: AXUIElement]
    private let frames: [String: CGRect]
    private let nodes: [String: UIElementNode]

    init(elements: [String: AXUIElement], frames: [String: CGRect], nodes: [String: UIElementNode]) {
        self.elements = elements
        self.frames = frames
        self.nodes = nodes
    }

    public func element(for id: String) -> AXUIElement? { elements[id] }
    public func frame(for id: String) -> CGRect? { frames[id] }
    public var ids: [String] { Array(elements.keys) }
    public func hasElement(_ id: String) -> Bool { nodes[id] != nil }
    public func node(for id: String) -> UIElementNode? { nodes[id] }

    /// Re-reads the live position+size from AX. Returns nil if the id is unknown
    /// or the element no longer exists (destroyed, scrolled out of an offscreen
    /// container that recycles its children, etc.).
    public func liveFrame(for id: String) -> CGRect? {
        guard let el = elements[id] else { return nil }
        return AXAttr.frame(el)
    }
}
