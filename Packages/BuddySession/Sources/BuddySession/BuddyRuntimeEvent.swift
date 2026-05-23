import Foundation

/// Tour-related and lesson-related runtime events the app emits as synthetic
/// `[BUDDY_EVENT]` turns so the persona can narrate without having to call any tool.
public enum BuddyRuntimeEvent: Sendable, Equatable {
    case tourStep(index: Int, total: Int, step: TourStep)
    case tourComplete
    case tourAborted(reason: TourAbortReason)
    case lessonStarted(
        id: String, title: String, intro: String, teachingStance: String?,
        steps: [String], wrapup: String?, suggestedNext: [String], estimatedMinutes: Int?
    )
    case lessonStepAdvanced(index: Int, total: Int?, instruction: String, teach: String?)
    case lessonFinished(wrapup: String?, suggestedNext: [String])
    case lessonExited
}

extension BuddyRuntimeEvent: Encodable {
    private enum CodingKeys: String, CodingKey {
        case type, index, total, label, role, reason, title, intro, steps
        case elementID = "element_id"
        case instruction
        case teach
        case teachingStance = "teaching_stance"
        case wrapup
        case suggestedNext = "suggested_next"
        case estimatedMinutes = "estimated_minutes"
        case lessonID = "lesson_id"
    }

    private enum EventType: String, Encodable {
        case tourStep = "tour_step"
        case tourComplete = "tour_complete"
        case tourAborted = "tour_aborted"
        case lessonStarted = "lesson_started"
        case lessonStepAdvanced = "lesson_step_advanced"
        case lessonFinished = "lesson_finished"
        case lessonExited = "lesson_exited"
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
        case .lessonStarted(let id, let title, let intro, let teachingStance,
                            let steps, let wrapup, let suggestedNext, let estimatedMinutes):
            try c.encode(EventType.lessonStarted, forKey: .type)
            try c.encode(id, forKey: .lessonID)
            try c.encode(title, forKey: .title)
            try c.encode(intro, forKey: .intro)
            try c.encodeIfPresent(teachingStance, forKey: .teachingStance)
            try c.encode(steps, forKey: .steps)
            try c.encodeIfPresent(wrapup, forKey: .wrapup)
            try c.encode(suggestedNext, forKey: .suggestedNext)
            try c.encodeIfPresent(estimatedMinutes, forKey: .estimatedMinutes)
        case .lessonStepAdvanced(let index, let total, let instruction, let teach):
            try c.encode(EventType.lessonStepAdvanced, forKey: .type)
            try c.encode(index, forKey: .index)
            try c.encodeIfPresent(total, forKey: .total)
            try c.encode(instruction, forKey: .instruction)
            try c.encodeIfPresent(teach, forKey: .teach)
        case .lessonFinished(let wrapup, let suggestedNext):
            try c.encode(EventType.lessonFinished, forKey: .type)
            try c.encodeIfPresent(wrapup, forKey: .wrapup)
            try c.encode(suggestedNext, forKey: .suggestedNext)
        case .lessonExited:
            try c.encode(EventType.lessonExited, forKey: .type)
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
