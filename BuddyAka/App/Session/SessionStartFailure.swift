import Foundation

/// Synchronous failures from `SessionCoordinator.start()` that the caller must route in UI
/// (block the wizard, jump to the API Key tab, etc.). All other errors are written to
/// `SessionCoordinator.lastError` and surfaced via the unified alert on `MainWindow`.
enum SessionStartFailure: Error, Equatable {
    case missingPermissions
    case missingAPIKey
}

@MainActor
struct SessionStartRouting {
    var onMissingPermissions: () -> Void
    var onMissingAPIKey: () -> Void
}
