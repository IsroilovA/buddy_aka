import Foundation
import Testing
@testable import BuddyVoice

@Suite("Outbound encoding")
struct OutboundEncodingTests {

    @Test("Setup envelope encodes camelCase fields with model, modalities, system instruction, no-interruption")
    func setupEncodes() throws {
        let envelope = ClientSetupEnvelope(
            setup: ClientSetup(
                model: "models/gemini-3.1-flash-live-preview",
                generationConfig: GenerationConfig(responseModalities: ["AUDIO"], speechConfig: nil),
                systemInstruction: SystemInstruction(parts: [TextPart(text: "Be brief.")]),
                realtimeInputConfig: RealtimeInputConfig(activityHandling: "START_OF_ACTIVITY_INTERRUPTS"),
                tools: nil
            )
        )
        let data = try JSONEncoder().encode(envelope)
        let dict = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let setup = try #require(dict["setup"] as? [String: Any])
        #expect(setup["model"] as? String == "models/gemini-3.1-flash-live-preview")

        let gc = try #require(setup["generationConfig"] as? [String: Any])
        #expect(gc["responseModalities"] as? [String] == ["AUDIO"])
        // No voice selected -> speechConfig must be absent on the wire, not null.
        #expect(gc["speechConfig"] == nil)

        let si = try #require(setup["systemInstruction"] as? [String: Any])
        let parts = try #require(si["parts"] as? [[String: Any]])
        #expect(parts.first?["text"] as? String == "Be brief.")

        let rtc = try #require(setup["realtimeInputConfig"] as? [String: Any])
        #expect(rtc["activityHandling"] as? String == "START_OF_ACTIVITY_INTERRUPTS")
    }

    @Test("Setup with a voice selection writes the documented speechConfig path")
    func setupEncodesVoice() throws {
        let envelope = ClientSetupEnvelope(
            setup: ClientSetup(
                model: "models/gemini-3.1-flash-live-preview",
                generationConfig: GenerationConfig(
                    responseModalities: ["AUDIO"],
                    speechConfig: SpeechConfig(voiceConfig: VoiceConfigWire(
                        prebuiltVoiceConfig: PrebuiltVoiceConfigWire(voiceName: "Puck")
                    ))
                ),
                systemInstruction: SystemInstruction(parts: [TextPart(text: "Be brief.")]),
                realtimeInputConfig: RealtimeInputConfig(activityHandling: "START_OF_ACTIVITY_INTERRUPTS"),
                tools: nil
            )
        )
        let data = try JSONEncoder().encode(envelope)
        let dict = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let setup = try #require(dict["setup"] as? [String: Any])
        let gc = try #require(setup["generationConfig"] as? [String: Any])
        let sc = try #require(gc["speechConfig"] as? [String: Any])
        let vc = try #require(sc["voiceConfig"] as? [String: Any])
        let pvc = try #require(vc["prebuiltVoiceConfig"] as? [String: Any])
        #expect(pvc["voiceName"] as? String == "Puck")
    }

    @Test("Setup envelope never carries languageCode — current Live model is native-audio and rejects it")
    func setupOmitsLanguageCode() throws {
        // Builds the same wire shape GeminiLiveClient produces. If a future change
        // adds `languageCode` to the GenerationConfig / SpeechConfig structs, this
        // test fails — that's the signal to revisit whether we've moved off the
        // native-audio model.
        let envelope = ClientSetupEnvelope(
            setup: ClientSetup(
                model: "models/gemini-3.1-flash-live-preview",
                generationConfig: GenerationConfig(
                    responseModalities: ["AUDIO"],
                    speechConfig: SpeechConfig(voiceConfig: VoiceConfigWire(
                        prebuiltVoiceConfig: PrebuiltVoiceConfigWire(voiceName: "Puck")
                    ))
                ),
                systemInstruction: SystemInstruction(parts: [TextPart(text: "Be brief.")]),
                realtimeInputConfig: RealtimeInputConfig(activityHandling: "START_OF_ACTIVITY_INTERRUPTS"),
                tools: nil
            )
        )
        let data = try JSONEncoder().encode(envelope)
        let raw = try #require(String(data: data, encoding: .utf8))
        #expect(!raw.contains("languageCode"))
        #expect(!raw.contains("language_code"))
    }

    @Test("PrebuiltVoices.curated lists the 6 voices and the default ID is present")
    func curatedCatalog() {
        let names = PrebuiltVoices.curated.map(\.id)
        #expect(names == ["Puck", "Charon", "Fenrir", "Aoede", "Leda", "Zephyr"])
        #expect(PrebuiltVoices.curated.filter { $0.gender == .male }.count == 3)
        #expect(PrebuiltVoices.curated.filter { $0.gender == .female }.count == 3)
        #expect(PrebuiltVoices.voice(forID: PrebuiltVoices.defaultID) != nil)
    }

    @Test("PersonaPrompt branches embed the chosen language's directive")
    func personaPromptLanguageBranches() {
        let dynamic = PersonaPrompt.v1(language: .dynamic)
        let ru      = PersonaPrompt.v1(language: .ru)
        let uz      = PersonaPrompt.v1(language: .uz)
        let en      = PersonaPrompt.v1(language: .en)

        // Dynamic defaults to Russian and follows the user's language thereafter.
        #expect(dynamic.contains("DEFAULT to Russian"))

        // Locked languages embed the hard rule.
        #expect(ru.contains("ALWAYS reply in RUSSIAN"))
        #expect(!ru.contains("DEFAULT to Russian"))

        #expect(uz.contains("ALWAYS reply in UZBEK using LATIN script"))
        #expect(uz.contains("NEVER use Cyrillic Uzbek"))

        #expect(en.contains("ALWAYS reply in ENGLISH"))
    }

    @Test("PersonaPrompt always includes lesson protocol section")
    func personaPromptLessonProtocol() {
        let prompt = PersonaPrompt.compose(PersonaContext(language: .en))
        #expect(prompt.contains("LESSON MODE"))
        #expect(prompt.contains("list_lessons"))
        #expect(prompt.contains("start_lesson"))
        #expect(prompt.contains("advance_lesson_step"))
        #expect(prompt.contains("lesson_step_advanced"))
        #expect(prompt.contains("GUIDELINE, not a script"))
    }

    @Test("realtimeInput envelope base64-encodes audio with the right mime type")
    func realtimeInputEncodes() throws {
        let pcm = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let envelope = ClientRealtimeAudioEnvelope(
            realtimeInput: RealtimeInputAudio(
                audio: InlineDataOut(
                    mimeType: GeminiLiveWire.inputMimeType,
                    data: pcm.base64EncodedString()
                )
            )
        )
        let data = try JSONEncoder().encode(envelope)
        let dict = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rt = try #require(dict["realtimeInput"] as? [String: Any])
        let audio = try #require(rt["audio"] as? [String: Any])
        #expect(audio["mimeType"] as? String == "audio/pcm;rate=16000")
        let b64 = try #require(audio["data"] as? String)
        #expect(Data(base64Encoded: b64) == pcm)
    }
}
