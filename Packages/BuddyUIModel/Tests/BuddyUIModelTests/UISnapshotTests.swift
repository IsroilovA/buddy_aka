import CoreGraphics
import Foundation
import Testing
@testable import BuddyUIModel

@Suite("UISnapshot wire shape")
struct UISnapshotTests {
    @Test("round-trips normalized snapshot")
    func roundTrip() throws {
        let snapshot = UISnapshot(
            app: "com.apple.Safari",
            windowTitle: "Soliq",
            url: "https://my.soliq.uz",
            elements: [
                UIElementNode(
                    id: "d_1",
                    source: .dom,
                    role: .button,
                    label: "Submit",
                    description: "Main action",
                    value: nil,
                    hasValue: false,
                    enabled: true,
                    focused: false,
                    frame: UIFrame(x: 10, y: 20, w: 100, h: 40),
                    metadata: ["tag": "button"]
                )
            ],
            stats: UISnapshotStats(scanned: 5, kept: 1, truncated: false, elapsedMs: 12)
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UISnapshot.self, from: data)
        #expect(decoded == snapshot)
    }
}

@Suite("UI normalization")
struct UINormalizationTests {
    @Test("maps AX and DOM roles to neutral roles")
    func roleMapping() {
        #expect(UINormalization.axRole("AXButton").0 == .button)
        #expect(UINormalization.axRole("AXTextField").0 == .textField)
        #expect(UINormalization.domRole(tag: "input", role: nil, type: "password").0 == .passwordField)
        #expect(UINormalization.domRole(tag: "a", role: nil).0 == .link)
    }

    @Test("detects sensitive field labels")
    func sensitiveFields() {
        #expect(UINormalization.isSensitiveField(role: .textField, label: "STIR", description: nil, placeholder: nil, inputType: nil, name: nil, id: nil))
        #expect(UINormalization.isSensitiveField(role: .textField, label: "OTP code", description: nil, placeholder: nil, inputType: nil, name: nil, id: nil))
        #expect(!UINormalization.isSensitiveField(role: .button, label: "Submit", description: nil, placeholder: nil, inputType: nil, name: nil, id: nil))
    }

    @Test("truncates text with ASCII ellipsis")
    func cleanTextTruncates() {
        #expect(UINormalization.cleanText("one   two\nthree", maxLength: 10) == "one two...")
        #expect(UINormalization.cleanText("abcdef", maxLength: 2) == "ab")
        #expect(UINormalization.cleanText("abcdef", maxLength: 0) == nil)
    }
}
