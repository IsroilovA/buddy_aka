import Foundation

/// Tour-related runtime events the app emits as synthetic `[BUDDY_EVENT]`
/// turns so the persona can narrate without having to call any tool.
public enum BuddyRuntimeEvent: Sendable, Equatable {
    case tourStep(index: Int, total: Int, step: TourStep)
    case tourComplete
    case tourAborted(reason: TourAbortReason)
}

extension BuddyRuntimeEvent: Encodable {
    private enum CodingKeys: String, CodingKey {
        case type, index, total, label, role, reason
        case elementID = "element_id"
    }

    private enum EventType: String, Encodable {
        case tourStep = "tour_step"
        case tourComplete = "tour_complete"
        case tourAborted = "tour_aborted"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .tourStep(let index, let total, let step):
            try c.encode(EventType.tourStep, forKey: .type)
            try c.encode(index, forKey: .index)
            try c.encode(total, forKey: .total)
            try c.encode(step.elementID, forKey: .elementID)
            try c.encode(step.label, forKey: .label)
            try c.encode(step.role, forKey: .role)
        case .tourComplete:
            try c.encode(EventType.tourComplete, forKey: .type)
        case .tourAborted(let reason):
            try c.encode(EventType.tourAborted, forKey: .type)
            try c.encode(reason, forKey: .reason)
        }
    }
}

extension BuddyRuntimeEvent {
    private static let encoder = JSONEncoder()

    /// `[BUDDY_EVENT] <json>` wire format consumed by the persona prompt.
    public func envelope() -> String {
        guard let data = try? Self.encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return #"[BUDDY_EVENT] {"type":"encoding_failed"}"#
        }
        return "[BUDDY_EVENT] \(json)"
    }
}
