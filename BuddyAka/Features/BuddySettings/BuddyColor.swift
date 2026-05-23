import SwiftUI

struct BuddyColor: RawRepresentable, Equatable {
    var rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.controlAccentColor
        let r = Int((ns.redComponent   * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent  * 255).rounded())
        let a = Int((ns.alphaComponent * 255).rounded())
        self.rawValue = String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    var color: Color {
        if rawValue == Self.accentSentinel { return .accentColor }
        let hex = rawValue.hasPrefix("#") ? String(rawValue.dropFirst()) : rawValue
        guard hex.count == 8, let v = UInt32(hex, radix: 16) else { return .accentColor }
        return Color(
            .sRGB,
            red:     Double((v >> 24) & 0xFF) / 255.0,
            green:   Double((v >> 16) & 0xFF) / 255.0,
            blue:    Double((v >>  8) & 0xFF) / 255.0,
            opacity: Double( v        & 0xFF) / 255.0
        )
    }

    private static let accentSentinel = "@accent"
    static let systemAccent = BuddyColor(rawValue: accentSentinel)
    static let storageKey = "buddyColor"
}
