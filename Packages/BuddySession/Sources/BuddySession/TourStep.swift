import Foundation

/// One stop in a Tour Mode walkthrough. Frames are NOT stored — the coordinator
/// re-reads them from the pinned UI snapshot resolver on each tick so scroll-
/// induced shifts are picked up automatically and destroyed elements surface as
/// nil rather than as stale rectangles.
public struct TourStep: Sendable, Equatable {
    public let elementID: String
    public let label: String
    public let role: String

    public init(elementID: String, label: String, role: String) {
        self.elementID = elementID
        self.label = label
        self.role = role
    }
}

public enum TourAbortReason: String, Codable, Sendable, Equatable {
    case appChanged = "app_changed"
    case elementLost = "element_lost"
    case userStop = "user_stop"
}
