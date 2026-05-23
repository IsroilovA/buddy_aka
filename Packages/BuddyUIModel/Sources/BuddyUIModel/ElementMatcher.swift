import Foundation

public struct ElementMatcher: Codable, Sendable, Equatable {
    public let role: UIElementRole?
    public let scope: UIElementScope?
    public let label: String?
    public let labelContains: String?
    public let identifier: String?
    public let anyOf: [ElementMatcher]?

    enum CodingKeys: String, CodingKey {
        case role, scope, label, identifier
        case labelContains = "label_contains"
        case anyOf = "any_of"
    }

    public init(
        role: UIElementRole? = nil,
        scope: UIElementScope? = nil,
        label: String? = nil,
        labelContains: String? = nil,
        identifier: String? = nil,
        anyOf: [ElementMatcher]? = nil
    ) {
        self.role = role
        self.scope = scope
        self.label = label
        self.labelContains = labelContains
        self.identifier = identifier
        self.anyOf = anyOf
    }

    public var isEmpty: Bool {
        role == nil
            && scope == nil
            && (label?.isEmpty ?? true)
            && (labelContains?.isEmpty ?? true)
            && (identifier?.isEmpty ?? true)
            && (anyOf?.isEmpty ?? true)
    }
}
