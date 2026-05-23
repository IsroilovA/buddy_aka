import Foundation

/// User-selectable language for the Buddy persona. Lives in BuddyVoice so the
/// persona prompt and the voice-audition sample text can share one source of truth.
///
/// `.dynamic` preserves the original behaviour: the model greets in Russian and
/// then matches whatever language the user replies in. The other cases pin the
/// persona to one language — even if the user speaks a different language back,
/// the model answers in the pinned language.
///
/// We deliberately do NOT translate this into a `speechConfig.languageCode` wire
/// field: the current Gemini Live model (`gemini-3.1-flash-live-preview`) is
/// native-audio and rejects that field. Steering happens entirely through the
/// system instruction.
public enum BuddyLanguage: String, Sendable, Hashable, CaseIterable, Identifiable {
    case dynamic
    case uz
    case ru
    case en

    public var id: String { rawValue }

    public static let `default`: BuddyLanguage = .dynamic

    /// Text spoken by the voice-picker audition when this language is selected.
    /// Not run through the localization catalog — the whole point is to preview
    /// the chosen language, not the macOS UI locale.
    public var auditionSampleText: String {
        switch self {
        case .uz:      return "Salom! Men Buddyman, sizga yo'l ko'rsataman."
        case .ru:      return "Привет! Я Buddy, помогу разобраться с интерфейсом."
        case .en:      return "Hi! I'm Buddy — your pocket guide to interfaces."
        case .dynamic: return Self.ru.auditionSampleText
        }
    }
}
