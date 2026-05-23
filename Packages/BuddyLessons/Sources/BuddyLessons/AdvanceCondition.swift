import BuddyUIModel
import Foundation

public enum AdvanceCondition: Sendable, Equatable {
    case focusedElementChanges
    case windowChanges
    case valueEquals(String)
    case valueStartsWith(String)
    case valueContains(String)
    case valueMatches(regex: String)
    case elementAppears(ElementMatcher)
    case elementDisappears(ElementMatcher)
    case urlContains(String)
    case userSaidContinue
}

public extension AdvanceCondition {
    var wireName: String {
        switch self {
        case .focusedElementChanges: return "focused_element_changes"
        case .windowChanges: return "window_changes"
        case .valueEquals: return "value_equals"
        case .valueStartsWith: return "value_starts_with"
        case .valueContains: return "value_contains"
        case .valueMatches: return "value_matches"
        case .elementAppears: return "element_appears"
        case .elementDisappears: return "element_disappears"
        case .urlContains: return "url_contains"
        case .userSaidContinue: return "user_said_continue"
        }
    }
}
