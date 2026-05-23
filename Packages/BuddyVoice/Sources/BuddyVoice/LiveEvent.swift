import Foundation

public enum LiveEvent: Sendable, Equatable {
    case connected
    case audioChunk(Data)
    case inputTranscript(String)
    case outputTranscript(String)
    case turnComplete
    case interrupted
    case toolCall(ToolCall)
    case toolCallCancellation(ids: [String])
    case goAway(reason: String?)
    case sessionResumptionUpdate(handle: String?, resumable: Bool)
    case disconnected(GeminiLiveError?)
}

public struct ToolCall: Sendable, Equatable {
    public let name: String
    public let id: String
    public let argsJSON: Data

    public init(name: String, id: String, argsJSON: Data) {
        self.name = name
        self.id = id
        self.argsJSON = argsJSON
    }
}
