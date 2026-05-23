import Foundation

public struct LiveSessionConfig: Sendable {
    public let systemInstruction: String
    public let tools: [Tool]
    public let voice: VoiceSelection?
    public let language: BuddyLanguage

    public init(
        systemInstruction: String,
        tools: [Tool] = [],
        voice: VoiceSelection? = nil,
        language: BuddyLanguage = .default
    ) {
        self.systemInstruction = systemInstruction
        self.tools = tools
        self.voice = voice
        self.language = language
    }
}

public struct VoiceSelection: Sendable, Equatable, Hashable {
    public let voiceName: String

    public init(voiceName: String) {
        self.voiceName = voiceName
    }
}
