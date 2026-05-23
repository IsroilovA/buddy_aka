import Foundation

public enum BuddySignal: String, Sendable, Equatable, CaseIterable {
    case sessionStarted = "session_started"
    case targetClicked = "target_clicked"
    case screenChanged = "screen_changed"
    case userClickedElsewhere = "user_clicked_elsewhere"
    case idleTimeout = "idle_timeout"
}
