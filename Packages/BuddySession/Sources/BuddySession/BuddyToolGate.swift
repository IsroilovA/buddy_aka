import Foundation

public enum BuddySessionMode: Sendable, Equatable {
    case live
    case guiding
    case settling
    case touringActive
    case touringPaused
    case other
}

public enum BuddyToolRejection: String, Sendable, Equatable {
    case tourActive = "tour_active"
    case tourAlreadyActive = "tour_already_active"
    case noActiveTour = "no_active_tour"
    case tourNotPaused = "tour_not_paused"
    case sessionBusy = "session_busy"
}

public enum BuddyToolGate {
    public static func rejection(for toolName: String, mode: BuddySessionMode) -> BuddyToolRejection? {
        switch toolName {
        case "start_tour":
            switch mode {
            case .live:
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
            case .live, .guiding, .settling, .other:
                return nil
            }
        case "stop_tour":
            switch mode {
            case .touringActive, .touringPaused:
                return nil
            case .live, .guiding, .settling, .other:
                return .noActiveTour
            }
        case "resume_tour":
            switch mode {
            case .touringPaused:
                return nil
            case .touringActive:
                return .tourNotPaused
            case .live, .guiding, .settling, .other:
                return .noActiveTour
            }
        default:
            return nil
        }
    }
}
