import BuddyVoice
import Foundation
import Observation

@MainActor
@Observable
final class BuddySettings {
    var color: BuddyColor {
        didSet { UserDefaults.standard.set(color.rawValue, forKey: Self.colorKey) }
    }

    var voiceName: String {
        didSet { UserDefaults.standard.set(voiceName, forKey: Self.voiceNameKey) }
    }

    var language: BuddyLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey) }
    }

    var selectedLessonID: String? {
        didSet {
            if let id = selectedLessonID, !id.isEmpty {
                UserDefaults.standard.set(id, forKey: Self.selectedLessonKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.selectedLessonKey)
            }
        }
    }

    private static let colorKey = BuddyColor.storageKey
    private static let voiceNameKey = "buddyVoiceName"
    private static let languageKey = "buddyLanguage"
    private static let selectedLessonKey = "buddySelectedLessonID"

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.colorKey)
            ?? BuddyColor.systemAccent.rawValue
        self.color = BuddyColor(rawValue: raw)

        self.voiceName = UserDefaults.standard.string(forKey: Self.voiceNameKey)
            ?? PrebuiltVoices.defaultID

        let storedLanguage = UserDefaults.standard.string(forKey: Self.languageKey)
            .flatMap(BuddyLanguage.init(rawValue:))
        self.language = storedLanguage ?? .default

        let storedLesson = UserDefaults.standard.string(forKey: Self.selectedLessonKey)
        self.selectedLessonID = (storedLesson?.isEmpty == false) ? storedLesson : nil
    }
}
