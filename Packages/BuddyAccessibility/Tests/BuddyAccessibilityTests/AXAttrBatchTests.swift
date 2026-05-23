import CoreGraphics
import Testing
@testable import BuddyAccessibility

@Suite("AXAttrBatch and bestLabel precedence")
struct AXAttrBatchTests {
    @Test("title wins over description and help")
    func titleWins() {
        let attrs = AXAttrBatch(title: "Save", description: "Save the file", help: "Saves the file to disk")
        #expect(AXExtractor.bestLabel(from: attrs) == "Save")
    }

    @Test("description falls back when title is nil")
    func descriptionFallback() {
        let attrs = AXAttrBatch(description: "Close window", help: "Closes the active window")
        #expect(AXExtractor.bestLabel(from: attrs) == "Close window")
    }

    @Test("description falls back when title is empty")
    func descriptionFallbackOnEmptyTitle() {
        let attrs = AXAttrBatch(title: "", description: "Reset", help: "Reset to defaults")
        #expect(AXExtractor.bestLabel(from: attrs) == "Reset")
    }

    @Test("help is the last fallback")
    func helpFallback() {
        let attrs = AXAttrBatch(title: "", description: "", help: "Tooltip-only label")
        #expect(AXExtractor.bestLabel(from: attrs) == "Tooltip-only label")
    }

    @Test("nil when nothing is set")
    func nilWhenEmpty() {
        let attrs = AXAttrBatch()
        #expect(AXExtractor.bestLabel(from: attrs) == nil)
    }

    @Test("stored fields survive memberwise init")
    func memberwiseInit() {
        let frame = CGRect(x: 1, y: 2, width: 3, height: 4)
        let attrs = AXAttrBatch(
            role: "AXButton",
            subrole: "AXCloseButton",
            title: "x",
            description: "close",
            help: "Close window",
            identifier: "close-btn",
            enabled: true,
            focused: false,
            frame: frame
        )
        #expect(attrs.role == "AXButton")
        #expect(attrs.subrole == "AXCloseButton")
        #expect(attrs.identifier == "close-btn")
        #expect(attrs.enabled == true)
        #expect(attrs.focused == false)
        #expect(attrs.frame == frame)
    }
}
