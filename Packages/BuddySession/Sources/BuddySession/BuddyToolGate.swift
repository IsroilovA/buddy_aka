import Foundation

public enum BuddySessionMode: Sendable, Equatable {
    case live
    case guiding
    case settling
    case touringActive
    case touringPaused
    case lessonActive
    case other
}

public enum BuddyToolRejection: String, Sendable, Equatable {
    case tourActive = "tour_active"
    case tourAlreadyActive = "tour_already_active"
    case noActiveTour = "no_active_tour"
    case tourNotPaused = "tour_not_paused"
    case noActiveLesson = "no_active_lesson"
    case lessonAlreadyActive = "lesson_already_active"
    case sessionBusy = "session_busy"
}

public enum BuddyToolGate {
    public static func rejection(for toolName: String, mode: BuddySessionMode) -> BuddyToolRejection? {
        switch toolName {
        case "start_tour":
            switch mode {
            case .live, .lessonActive:
                return nil
            case .touringActive, .touringPaused:
                return .tourAlreadyActive
            case .guiding, .settling, .other:
                return .sessionBusy
            }
        case "point_to_element":
            switch mode {
            case .touringActive, .touringPaused:
                return .tourActive
            case .live, .guiding, .settling, .lessonActive, .other:
                return nil
            }
        case "stop_tour":
            switch mode {
            case .touringActive, .touringPaused:
                return nil
            case .live, .guiding, .settling, .lessonActive, .other:
                return .noActiveTour
            }
        case "resume_tour":
            switch mode {
            case .touringPaused:
                return nil
            case .touringActive:
                return .tourNotPaused
            case .live, .guiding, .settling, .lessonActive, .other:
                return .noActiveTour
            }
        case "exit_lesson":
            switch mode {
            case .lessonActive:
                return nil
            case .live, .guiding, .settling, .touringActive, .touringPaused, .other:
                return .noActiveLesson
            }
        case "start_lesson":
            switch mode {
            case .live:
                return nil
            case .lessonActive:
                return .lessonAlreadyActive
            case .touringActive, .touringPaused:
                return .sessionBusy
            case .guiding, .settling, .other:
                return .sessionBusy
            }
        case "advance_lesson_step":
            switch mode {
            case .lessonActive:
                return nil
            case .live, .guiding, .settling, .touringActive, .touringPaused, .other:
                return .noActiveLesson
            }
        case "list_lessons", "stop_pointing":
            return nil
        default:
            return nil
        }
    }
}
