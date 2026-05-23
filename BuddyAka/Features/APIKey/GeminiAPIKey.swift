import Foundation

enum GeminiAPIKey {
    static let keychainKey = "gemini.apiKey"

    static func read() throws -> String? {
        try KeychainStore.get(key: keychainKey)
    }

    static func clear() throws {
        try KeychainStore.delete(key: keychainKey)
    }
}
