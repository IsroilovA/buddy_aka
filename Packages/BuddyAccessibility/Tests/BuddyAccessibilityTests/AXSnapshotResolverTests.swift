import Foundation
import Testing
import BuddyUIModel
@testable import BuddyAccessibility

@Suite("AXSnapshotResolver")
struct AXSnapshotResolverTests {

    @Test("Empty resolver returns nil for element, frame, and liveFrame on any id")
    func emptyResolver() {
        let r = AXSnapshotResolver(elements: [:], frames: [:], nodes: [:])
        #expect(r.element(for: "e_1") == nil)
        #expect(r.frame(for: "e_1") == nil)
        #expect(r.liveFrame(for: "e_1") == nil)
        #expect(r.node(for: "e_1") == nil)
        #expect(r.ids.isEmpty)
    }

    // Live-frame happy-path requires a real AXUIElement bound to a running app,
    // which can't be constructed in a unit test sandbox. Exercised manually via
    // `axdump` CLI and the in-app session.
}
