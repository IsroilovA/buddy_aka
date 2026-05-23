import CoreGraphics
import Foundation

// "Actionable" predicate. We aggressively trim scaffolding (groups, scroll areas,
// splitters) and keep things a guide can point at: buttons, links, fields, menus,
// labeled cells, and anything carrying an AXIdentifier.
enum AXFilter {
    static let actionableRoles: Set<String> = [
        "AXButton",
        "AXLink",
        "AXMenuItem",
        "AXMenuButton",
        "AXPopUpButton",
        "AXCheckBox",
        "AXRadioButton",
        "AXTextField",
        "AXTextArea",
        "AXSearchField",
        "AXComboBox",
        "AXTab",
        "AXDisclosureTriangle",
        "AXSlider",
        "AXIncrementor",
        "AXStepper",
        "AXSwitch",
        "AXImage",          // often clickable in web UIs
    ]

    // Roles where a label/identifier makes the element worth keeping.
    static let labeledOnlyRoles: Set<String> = [
        "AXStaticText",
        "AXCell",
        "AXRow",
        "AXOutlineRow",
    ]

    struct Candidate {
        let role: String
        let label: String?
        let identifier: String?
        let frame: CGRect?
        let enabled: Bool
    }

    static func keep(_ c: Candidate, onScreenOnly: Bool, screenUnion: CGRect?) -> Bool {
        guard c.enabled else { return false }
        if onScreenOnly, let frame = c.frame, let bounds = screenUnion {
            if frame.isEmpty || !bounds.intersects(frame) { return false }
        }
        if c.identifier != nil, c.identifier?.isEmpty == false { return true }
        if actionableRoles.contains(c.role) {
            return c.frame.map { !$0.isEmpty } ?? false
        }
        if labeledOnlyRoles.contains(c.role) {
            return (c.label?.isEmpty == false) && (c.frame.map { !$0.isEmpty } ?? false)
        }
        return false
    }
}
