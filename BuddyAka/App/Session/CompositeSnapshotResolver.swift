import ApplicationServices
import BuddyAccessibility
import BuddyUIModel
import CoreGraphics
import Foundation

/// Wraps several `UISnapshotResolving` instances (typically one for the focused
/// app window plus one each for the menu bar and Dock). Each lookup walks the
/// child list and returns the first match.
///
/// IDs across children are kept disjoint by prefixing (`aw_`, `mb_`, `dk_`), so
/// the order of children does not affect correctness — but a deterministic
/// order keeps logs predictable.
@MainActor
final class CompositeSnapshotResolver: @MainActor UISnapshotResolving {
    private let children: [any UISnapshotResolving]

    init(_ children: [any UISnapshotResolving]) {
        self.children = children
    }

    var ids: [String] {
        children.flatMap(\.ids)
    }

    func hasElement(_ id: String) -> Bool {
        children.contains { $0.hasElement(id) }
    }

    func node(for id: String) -> UIElementNode? {
        for child in children {
            if let node = child.node(for: id) { return node }
        }
        return nil
    }

    func liveFrame(for id: String) -> CGRect? {
        for child in children {
            if let frame = child.liveFrame(for: id) { return frame }
        }
        return nil
    }

    func axElement(for id: String) -> AXUIElement? {
        for child in children {
            if let ax = child as? AXSnapshotResolver, let el = ax.element(for: id) {
                return el
            }
        }
        return nil
    }
}
