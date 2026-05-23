import BuddyVoice
import Foundation

extension GeminiLiveError {
    var localizedTitle: String {
        switch self {
        case .keyRejected:        return String(localized: "API key rejected")
        case .setupFailed:        return String(localized: "Couldn't start session")
        case .audioSetupFailed:   return String(localized: "Audio setup failed")
        case .network:            return String(localized: "Network error")
        case .protocol:           return String(localized: "Unexpected response")
        case .disconnected:       return String(localized: "Connection lost")
        }
    }

    var localizedMessage: String {
        switch self {
        case .keyRejected(let reason):
            if let reason, !reason.isEmpty {
                return String(format: String(localized: "Gemini rejected the API key: %@"), reason)
            }
            return String(localized: "Gemini rejected the API key.")
        case .setupFailed(let reason):
            return String(format: String(localized: "Couldn't start the Gemini session: %@"), reason)
        case .audioSetupFailed(let reason):
            return String(format: String(localized: "Couldn't initialize audio: %@"), reason)
        case .network(_, let reason):
            return String(format: String(localized: "Couldn't reach Gemini: %@"), reason)
        case .protocol(let reason):
            return String(format: String(localized: "Gemini sent an unexpected response: %@"), reason)
        case .disconnected(let reason):
            if let reason, !reason.isEmpty {
                return String(format: String(localized: "Connection lost: %@"), reason)
            }
            return String(localized: "Connection lost")
        }
    }
}
