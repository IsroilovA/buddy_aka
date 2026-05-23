import BuddyVoice
import SwiftUI

struct BuddySettingsView: View {
    @Environment(BuddySettings.self) private var settings
    @State private var audition: TTSAudition?
    @State private var auditionAPIKey: String?
    @State private var activeVoiceID: String?
    @State private var lastError: String?

    private var maleVoices: [PrebuiltVoice] {
        PrebuiltVoices.curated.filter { $0.gender == .male }
    }
    private var femaleVoices: [PrebuiltVoice] {
        PrebuiltVoices.curated.filter { $0.gender == .female }
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                ColorPicker(
                    selection: Binding(
                        get: { settings.color.color },
                        set: { settings.color = BuddyColor($0) }
                    ),
                    supportsOpacity: false
                ) {
                    Text(String(localized: "Buddy color"))
                }

                HStack {
                    Spacer()
                    Button(String(localized: "Reset to system accent")) {
                        settings.color = .systemAccent
                    }
                }
            } header: {
                Text(String(localized: "Appearance"))
            } footer: {
                Text(String(localized: "The cursor and pulse ring use this color."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(selection: $settings.language) {
                    ForEach(BuddyLanguage.allCases) { language in
                        Text(localizedName(for: language)).tag(language)
                    }
                } label: {
                    Text(String(localized: "Buddy language"))
                }
                .pickerStyle(.menu)
            } header: {
                Text(String(localized: "Language"))
            } footer: {
                Text(String(localized: "Buddy greets and replies in this language. Dynamic follows whatever you speak."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(maleVoices) { row(for: $0) }
            } header: {
                Text(String(localized: "Male"))
            }

            Section {
                ForEach(femaleVoices) { row(for: $0) }
            } header: {
                Text(String(localized: "Female"))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Voice applies on next session start."))
                    if let lastError {
                        Text(lastError)
                            .foregroundStyle(.red)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { refreshAPIKey() }
    }

    private func row(for voice: PrebuiltVoice) -> some View {
        VoiceRow(
            voice: voice,
            isSelected: settings.voiceName == voice.id,
            isAuditioning: activeVoiceID == voice.id,
            canAudition: auditionAPIKey != nil
        ) {
            settings.voiceName = voice.id
        } onAudition: {
            Task { await playSample(for: voice.id) }
        }
    }

    private func localizedName(for language: BuddyLanguage) -> String {
        // String(localized:) needs literal strings at the call site for extraction;
        // the four cases are a closed set so a switch keeps the catalog happy.
        switch language {
        case .dynamic: return String(localized: "Dynamic")
        case .uz:      return String(localized: "Uzbek")
        case .ru:      return String(localized: "Russian")
        case .en:      return String(localized: "English")
        }
    }

    private func refreshAPIKey() {
        do {
            let key = try GeminiAPIKey.read()
            auditionAPIKey = (key?.isEmpty == false) ? key : nil
        } catch {
            auditionAPIKey = nil
        }
    }

    private func playSample(for voiceID: String) async {
        // Re-read the key in case the user updated it in the API Key tab
        // since this view appeared.
        let currentKey: String?
        do {
            currentKey = try GeminiAPIKey.read()
        } catch {
            lastError = error.localizedDescription
            return
        }
        guard let key = currentKey, !key.isEmpty else {
            lastError = String(localized: "Set your API key in the API Key tab to audition voices.")
            return
        }
        if audition == nil || auditionAPIKey != key {
            audition = TTSAudition(apiKey: key)
            auditionAPIKey = key
        }
        guard let audition else { return }

        if activeVoiceID == voiceID {
            audition.stop()
            activeVoiceID = nil
            return
        }

        activeVoiceID = voiceID
        lastError = nil
        do {
            try await audition.sample(
                voiceName: voiceID,
                text: settings.language.auditionSampleText
            )
            // Sample is ~2–3s at 24kHz; sleep then revert state so the speaker icon
            // flips back to "play" once audio is done.
            try? await Task.sleep(for: .seconds(4))
            if activeVoiceID == voiceID {
                activeVoiceID = nil
            }
        } catch {
            lastError = error.localizedDescription
            activeVoiceID = nil
        }
    }
}
