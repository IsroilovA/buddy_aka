import Foundation

/// Identifies a target application (and optional URL substring) for a lesson.
/// Encoded in lesson frontmatter as `bundle_id: …` OR `url_match: …`.
public enum AppTarget: Sendable, Equatable {
    case bundleID(String)
    case urlMatch(String)

    public var humanLabel: String {
        switch self {
        case .bundleID(let id): return id
        case .urlMatch(let s): return s
        }
    }

    public func isSatisfied(byBundleID currentBundle: String?, currentURL: String?) -> Bool {
        switch self {
        case .bundleID(let want):
            guard let currentBundle else { return false }
            return currentBundle.caseInsensitiveCompare(want) == .orderedSame
        case .urlMatch(let needle):
            guard let url = currentURL, !url.isEmpty else { return false }
            return url.range(of: needle, options: [.caseInsensitive]) != nil
        }
    }
}

extension AppTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case bundleID = "bundle_id"
        case urlMatch = "url_match"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try c.decodeIfPresent(String.self, forKey: .bundleID), !id.isEmpty {
            self = .bundleID(id)
            return
        }
        if let url = try c.decodeIfPresent(String.self, forKey: .urlMatch), !url.isEmpty {
            self = .urlMatch(url)
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "AppTarget requires either bundle_id or url_match"
        ))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bundleID(let id): try c.encode(id, forKey: .bundleID)
        case .urlMatch(let url): try c.encode(url, forKey: .urlMatch)
        }
    }
}
