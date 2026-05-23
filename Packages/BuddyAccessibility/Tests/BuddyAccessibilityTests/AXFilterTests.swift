import CoreGraphics
import Testing
@testable import BuddyAccessibility

@Suite("AXFilter actionable predicate")
struct AXFilterTests {
    private let onScreen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let bounds: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func make(
        role: String,
        label: String? = nil,
        identifier: String? = nil,
        frame: CGRect? = nil,
        enabled: Bool = true
    ) -> AXFilter.Candidate {
        AXFilter.Candidate(role: role, label: label, identifier: identifier, frame: frame, enabled: enabled)
    }

    @Test("keeps a button with a frame on screen")
    func keepButton() {
        let c = make(role: "AXButton", label: "Save",
                     frame: CGRect(x: 10, y: 10, width: 100, height: 30))
        #expect(AXFilter.keep(c, onScreenOnly: true, screenUnion: bounds))
    }

    @Test("drops scaffolding roles without identifier")
    func dropGroup() {
        let c = make(role: "AXGroup", label: "container",
                     frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(!AXFilter.keep(c, onScreenOnly: true, screenUnion: bounds))
    }

    @Test("keeps any role when AXIdentifier is set")
    func keepByIdentifier() {
        let c = make(role: "AXGroup", identifier: "submit-region",
                     frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        #expect(AXFilter.keep(c, onScreenOnly: true, screenUnion: bounds))
    }

    @Test("drops off-screen elements when filter is on")
    func dropOffscreen() {
        let c = make(role: "AXButton", label: "Hidden",
                     frame: CGRect(x: 10_000, y: 10_000, width: 100, height: 30))
        #expect(!AXFilter.keep(c, onScreenOnly: true, screenUnion: bounds))
    }

    @Test("keeps off-screen elements when filter is off")
    func keepOffscreenWhenFilterOff() {
        let c = make(role: "AXButton", label: "Hidden",
                     frame: CGRect(x: 10_000, y: 10_000, width: 100, height: 30))
        #expect(AXFilter.keep(c, onScreenOnly: false, screenUnion: nil))
    }

    @Test("static text needs a label to count")
    func staticTextNeedsLabel() {
        let unlabeled = make(role: "AXStaticText",
                             frame: CGRect(x: 0, y: 0, width: 80, height: 20))
        let labeled = make(role: "AXStaticText", label: "Total",
                           frame: CGRect(x: 0, y: 0, width: 80, height: 20))
        #expect(!AXFilter.keep(unlabeled, onScreenOnly: true, screenUnion: bounds))
        #expect(AXFilter.keep(labeled, onScreenOnly: true, screenUnion: bounds))
    }

    @Test("zero-size frames are rejected")
    func zeroSize() {
        let c = make(role: "AXButton", label: "Phantom",
                     frame: CGRect(x: 100, y: 100, width: 0, height: 0))
        #expect(!AXFilter.keep(c, onScreenOnly: true, screenUnion: bounds))
    }

    @Test("disabled controls are rejected")
    func disabledControl() {
        let c = make(role: "AXButton", label: "Submit", frame: onScreen, enabled: false)
        #expect(!AXFilter.keep(c, onScreenOnly: true, screenUnion: bounds))
    }
}
