import Foundation

public struct LiveSessionConfig: Sendable {
    public let systemInstruction: String
    public let tools: [Tool]
    public let voice: VoiceSelection?
    public let language: BuddyLanguage
    /// Optional previous session handle. The client passes it in `sessionResumption.handle`
    /// so Gemini can resume the conversation in flight (up to 2h after disconnect).
    public let resumptionHandle: String?

    public init(
        systemInstruction: String,
        tools: [Tool] = [],
        voice: VoiceSelection? = nil,
        language: BuddyLanguage = .default,
        resumptionHandle: String? = nil
    ) {
        self.systemInstruction = systemInstruction
        self.tools = tools
        self.voice = voice
        self.language = language
        self.resumptionHandle = resumptionHandle
    }
}

public struct VoiceSelection: Sendable, Equatable, Hashable {
    public let voiceName: String

    public init(voiceName: String) {
        self.voiceName = voiceName
    }
}
