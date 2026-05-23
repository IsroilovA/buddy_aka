import Foundation

public enum GeminiLiveError: Error, Sendable, Equatable {
    case keyRejected(reason: String?)
    case setupFailed(reason: String)
    case audioSetupFailed(reason: String)
    case network(URLError.Code, String)
    case `protocol`(reason: String)
    case disconnected(reason: String?)
}
