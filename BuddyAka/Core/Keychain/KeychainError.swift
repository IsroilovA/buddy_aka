import Foundation

enum KeychainError: Error, CustomStringConvertible {
    case unexpectedStatus(OSStatus)
    case dataCorrupt

    var description: String {
        switch self {
        case .unexpectedStatus(let s): return "Keychain error (OSStatus \(s))"
        case .dataCorrupt:             return "Keychain data could not be decoded as UTF-8"
        }
    }
}
