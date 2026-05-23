import Foundation

public enum GeminiLiveWire {
    public static let defaultModel = "models/gemini-3.1-flash-live-preview"
    public static let endpoint = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
    public static let inputMimeType = "audio/pcm;rate=16000"
}

// MARK: - Outbound (Encodable — we control the shape)

struct ClientSetupEnvelope: Encodable {
    let setup: ClientSetup
}

struct ClientSetup: Encodable {
    let model: String
    let generationConfig: GenerationConfig
    let systemInstruction: SystemInstruction
    let realtimeInputConfig: RealtimeInputConfig
    let tools: [Tool]?
}

struct GenerationConfig: Encodable {
    /// Lives inside `generationConfig`, confirmed by server error message at v1beta. Some
    /// secondary docs claim top-level placement — they are wrong for this endpoint.
    let responseModalities: [String]
    /// Optional — when nil the field is absent on the wire and Gemini picks a default voice.
    let speechConfig: SpeechConfig?
}

struct SpeechConfig: Encodable {
    let voiceConfig: VoiceConfigWire
}

struct VoiceConfigWire: Encodable {
    let prebuiltVoiceConfig: PrebuiltVoiceConfigWire
}

struct PrebuiltVoiceConfigWire: Encodable {
    let voiceName: String
}

struct RealtimeInputConfig: Encodable {
    /// `"START_OF_ACTIVITY_INTERRUPTS"` lets the user cut Buddy off mid-narration —
    /// required for tour mode, where voice is the only "pause / ask" gesture the
    /// user has. The persona prompt accommodates being interrupted in guide mode too.
    let activityHandling: String
}

struct SystemInstruction: Encodable {
    let parts: [TextPart]
}

struct TextPart: Encodable {
    let text: String
}

struct ClientRealtimeAudioEnvelope: Encodable {
    let realtimeInput: RealtimeInputAudio
}

struct RealtimeInputAudio: Encodable {
    let audio: InlineDataOut
}

struct InlineDataOut: Encodable {
    let mimeType: String
    let data: String  // base64
}

/// Text turns from the client. `clientContent` appends to conversation history;
/// `turnComplete: true` asks the model to respond to the accumulated turn.
struct ClientContentEnvelope: Encodable {
    let clientContent: ClientContentBody
}

struct ClientContentBody: Encodable {
    let turns: [UserTurn]
    let turnComplete: Bool
}

struct UserTurn: Encodable {
    let role: String  // "user"
    let parts: [TextPart]
}

// MARK: - Inbound parsing
//
// Server frames are a small set of top-level keys (`setupComplete`, `serverContent`,
// `toolCall`, `goAway`). Tool-call `args` is a nested JSON object of unknown shape.
// JSONSerialization makes this easy without an AnyCodable dance.

enum ServerFrameParser {
    /// Parses a raw server JSON text frame into a sequence of LiveEvents.
    /// Returns an empty array for frames we don't act on (e.g., `goAway` is logged but not surfaced).
    /// Throws `GeminiLiveError.protocol` on malformed JSON or a structurally invalid frame.
    static func parse(_ data: Data) throws -> [LiveEvent] {
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw GeminiLiveError.protocol(reason: "invalid JSON: \(error.localizedDescription)")
        }
        guard let dict = obj as? [String: Any] else {
            throw GeminiLiveError.protocol(reason: "top-level frame is not an object")
        }

        var events: [LiveEvent] = []

        if dict["setupComplete"] != nil {
            events.append(.connected)
        }

        if let sc = dict["serverContent"] as? [String: Any] {
            if let modelTurn = sc["modelTurn"] as? [String: Any],
               let parts = modelTurn["parts"] as? [[String: Any]] {
                for part in parts {
                    if let inline = part["inlineData"] as? [String: Any],
                       let b64 = inline["data"] as? String,
                       let pcm = Data(base64Encoded: b64) {
                        events.append(.audioChunk(pcm))
                    } else if let text = part["text"] as? String, !text.isEmpty {
                        // Gemini fell back to text — surface so the caller can see the modality mismatch.
                        events.append(.outputTranscript(text))
                    }
                }
            }
            if let it = sc["inputTranscription"] as? [String: Any],
               let text = it["text"] as? String, !text.isEmpty {
                events.append(.inputTranscript(text))
            }
            if let ot = sc["outputTranscription"] as? [String: Any],
               let text = ot["text"] as? String, !text.isEmpty {
                events.append(.outputTranscript(text))
            }
            if let interrupted = sc["interrupted"] as? Bool, interrupted {
                events.append(.interrupted)
            }
            if let turnComplete = sc["turnComplete"] as? Bool, turnComplete {
                events.append(.turnComplete)
            }
        }

        if let tc = dict["toolCall"] as? [String: Any],
           let calls = tc["functionCalls"] as? [[String: Any]] {
            for call in calls {
                guard let name = call["name"] as? String else { continue }
                let id = (call["id"] as? String) ?? ""
                let argsBytes: Data
                if let args = call["args"] {
                    argsBytes = (try? JSONSerialization.data(withJSONObject: args, options: [])) ?? Data("null".utf8)
                } else {
                    argsBytes = Data("null".utf8)
                }
                events.append(.toolCall(ToolCall(name: name, id: id, argsJSON: argsBytes)))
            }
        }

        if let goAway = dict["goAway"] as? [String: Any] {
            events.append(.goAway(reason: goAway["timeLeft"] as? String))
        }

        return events
    }
}
