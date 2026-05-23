import Foundation

// Wire-format types for Gemini Live tool declarations and tool responses.
// Field names match the v1beta JSON exactly (camelCase) — see ai.google.dev/api/live.

public struct Tool: Encodable, Sendable {
    public let functionDeclarations: [FunctionDeclaration]

    public init(functionDeclarations: [FunctionDeclaration]) {
        self.functionDeclarations = functionDeclarations
    }
}

public struct FunctionDeclaration: Encodable, Sendable {
    public let name: String
    public let description: String
    public let parameters: Schema

    public init(name: String, description: String, parameters: Schema) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

// OpenAPI 3.0 subset. `type` is UPPERCASE on the wire — STRING, OBJECT, BOOLEAN, …
public struct Schema: Encodable, Sendable {
    public let type: SchemaType
    public let description: String?
    public let properties: [String: Schema]?
    public let required: [String]?
    // Backed by a reference type so Schema isn't recursive-by-value.
    // `[String: Schema]?` above works for the same reason — Dictionary's
    // storage is heap-allocated. `Optional<Schema>` would be inline, so we box.
    public var items: Schema? { itemsBox?.schema }
    private let itemsBox: SchemaBox?

    public init(
        type: SchemaType,
        description: String? = nil,
        properties: [String: Schema]? = nil,
        required: [String]? = nil,
        items: Schema? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.required = required
        self.itemsBox = items.map(SchemaBox.init)
    }

    private enum CodingKeys: String, CodingKey {
        case type, description, properties, required, items
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(properties, forKey: .properties)
        try c.encodeIfPresent(required, forKey: .required)
        try c.encodeIfPresent(items, forKey: .items)
    }

    public enum SchemaType: String, Encodable, Sendable {
        case object = "OBJECT"
        case string = "STRING"
        case boolean = "BOOLEAN"
        case number = "NUMBER"
        case integer = "INTEGER"
        case array = "ARRAY"
    }
}

private final class SchemaBox: @unchecked Sendable {
    let schema: Schema
    init(_ schema: Schema) { self.schema = schema }
}

// MARK: - Tool response (client → server)

public struct ToolResponse: Sendable {
    public let id: String
    public let name: String
    public let response: AnyEncodable

    public init(id: String, name: String, response: AnyEncodable) {
        self.id = id
        self.name = name
        self.response = response
    }
}

struct ClientToolResponseEnvelope: Encodable {
    let toolResponse: ToolResponseBody
}

struct ToolResponseBody: Encodable {
    let functionResponses: [FunctionResponse]
}

struct FunctionResponse: Encodable {
    let id: String
    let name: String
    let response: AnyEncodable
}

// MARK: - Type-erased Encodable

// Lets the dispatcher hand back tool-specific Encodable payloads without
// bleeding their types into the wire layer.
public struct AnyEncodable: @unchecked Sendable, Encodable {
    private let _encode: (Encoder) throws -> Void

    public init<T: Encodable>(_ value: T) {
        self._encode = { encoder in try value.encode(to: encoder) }
    }

    public func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
