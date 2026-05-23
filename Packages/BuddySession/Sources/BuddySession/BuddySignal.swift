import Foundation

public enum BuddySignal: String, Sendable, Equatable, CaseIterable {
    case sessionStarted = "session_started"
    case targetClicked = "target_clicked"
    case screenChanged = "screen_changed"
    case userClickedElsewhere = "user_clicked_elsewhere"
    case userClickedElsewhereScreenChanged = "user_clicked_elsewhere_screen_changed"
    case idleTimeout = "idle_timeout"
    case targetScrolledOffScreen = "target_scrolled_off_screen"
    case targetValueChanged = "target_value_changed"
    case lessonStepCompleted = "lesson_step_completed"
    case lessonFinished = "lesson_finished"
    case lessonExited = "lesson_exited"
}
