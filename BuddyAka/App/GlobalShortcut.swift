import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleBuddy = Self("toggleBuddy",
        default: .init(.b, modifiers: [.command, .shift]))
}
