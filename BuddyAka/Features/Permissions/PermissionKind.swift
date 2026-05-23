import Foundation

enum PermissionStatus {
    case notDetermined
    case granted
    case denied
}

enum PermissionKind: CaseIterable, Identifiable {
    case accessibility
    case screenCapture
    case microphone

    var id: Self { self }

    var title: String {
        switch self {
        case .accessibility: return String(localized: "Accessibility")
        case .screenCapture: return String(localized: "Screen Recording")
        case .microphone:    return String(localized: "Microphone")
        }
    }

    var subtitle: String {
        switch self {
        case .accessibility: return String(localized: "Lets BuddyAka read what's on screen so it can point at things.")
        case .screenCapture: return String(localized: "Needed to capture the focused window for visual context.")
        case .microphone:    return String(localized: "Used to hear your voice — audio never leaves your device unless you start a session.")
        }
    }

    var systemSettingsURL: String {
        switch self {
        case .accessibility: return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenCapture: return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .microphone:    return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        }
    }
}

struct PermissionRowModel: Identifiable {
    let kind: PermissionKind
    let title: String
    let subtitle: String?
    let status: PermissionStatus
    let url: String
    let grant: () -> Void

    var id: PermissionKind { kind }
}
