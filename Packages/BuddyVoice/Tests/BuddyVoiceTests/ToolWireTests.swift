import Foundation
import Testing
@testable import BuddyVoice

@Suite("Tool declaration + response encoding")
struct ToolWireTests {

    private func roundTrip<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let any = try JSONSerialization.jsonObject(with: data)
        return try #require(any as? [String: Any])
    }

    @Test("FunctionDeclaration encodes UPPERCASE schema types and camelCase top-level")
    func declarationEncodes() throws {
        let decl = FunctionDeclaration(
            name: "point_to_element",
            description: "move buddy",
            parameters: Schema(
                type: .object,
                properties: [
                    "element_id": Schema(type: .string, description: "id"),
                ],
                required: ["element_id"]
            )
        )
        let tool = Tool(functionDeclarations: [decl])
        let dict = try roundTrip(tool)
        let decls = try #require(dict["functionDeclarations"] as? [[String: Any]])
        let first = try #require(decls.first)
        #expect(first["name"] as? String == "point_to_element")
        #expect(first["description"] as? String == "move buddy")
        let params = try #require(first["parameters"] as? [String: Any])
        #expect(params["type"] as? String == "OBJECT")
        let props = try #require(params["properties"] as? [String: [String: Any]])
        #expect(props["element_id"]?["type"] as? String == "STRING")
        #expect(props["element_id"]?["description"] as? String == "id")
        #expect(params["required"] as? [String] == ["element_id"])
    }

    @Test("Schema omits nil fields entirely")
    func schemaOmitsNil() throws {
        let s = Schema(type: .boolean)
        let dict = try roundTrip(s)
        #expect(dict["type"] as? String == "BOOLEAN")
        #expect(dict["description"] == nil)
        #expect(dict["properties"] == nil)
        #expect(dict["required"] == nil)
        #expect(dict["items"] == nil)
    }

    @Test("Schema encodes array type with items sub-schema")
    func schemaArrayWithItems() throws {
        let s = Schema(
            type: .array,
            description: "ids",
            items: Schema(type: .string)
        )
        let dict = try roundTrip(s)
        #expect(dict["type"] as? String == "ARRAY")
        #expect(dict["description"] as? String == "ids")
        let items = try #require(dict["items"] as? [String: Any])
        #expect(items["type"] as? String == "STRING")
    }

    @Test("ClientSetup with tools serializes tools under setup")
    func setupCarriesTools() throws {
        let envelope = ClientSetupEnvelope(
            setup: ClientSetup(
                model: "models/x",
                generationConfig: GenerationConfig(responseModalities: ["AUDIO"], speechConfig: nil),
                systemInstruction: SystemInstruction(parts: [TextPart(text: "hi")]),
                realtimeInputConfig: RealtimeInputConfig(activityHandling: "START_OF_ACTIVITY_INTERRUPTS"),
                tools: [Tool(functionDeclarations: [
                    FunctionDeclaration(
                        name: "get_ui_tree",
                        description: "x",
                        parameters: Schema(type: .object)
                    )
                ])]
            )
        )
        let dict = try roundTrip(envelope)
        let setup = try #require(dict["setup"] as? [String: Any])
        let tools = try #require(setup["tools"] as? [[String: Any]])
        let decls = try #require(tools.first?["functionDeclarations"] as? [[String: Any]])
        #expect(decls.first?["name"] as? String == "get_ui_tree")
    }

    @Test("ClientSetup without tools omits the field entirely")
    func setupOmitsToolsWhenNil() throws {
        let envelope = ClientSetupEnvelope(
            setup: ClientSetup(
                model: "models/x",
                generationConfig: GenerationConfig(responseModalities: ["AUDIO"], speechConfig: nil),
                systemInstruction: SystemInstruction(parts: [TextPart(text: "hi")]),
                realtimeInputConfig: RealtimeInputConfig(activityHandling: "START_OF_ACTIVITY_INTERRUPTS"),
                tools: nil
            )
        )
        let dict = try roundTrip(envelope)
        let setup = try #require(dict["setup"] as? [String: Any])
        #expect(setup["tools"] == nil)
    }

    @Test("ClientContentEnvelope encodes text turns with turnComplete")
    func clientContentEnvelopeShape() throws {
        let env = ClientContentEnvelope(
            clientContent: ClientContentBody(
                turns: [UserTurn(role: "user", parts: [TextPart(text: "hi")])],
                turnComplete: true
            )
        )
        let dict = try roundTrip(env)
        #expect(Array(dict.keys) == ["clientContent"])
        let inner = try #require(dict["clientContent"] as? [String: Any])
        #expect(inner["turnComplete"] as? Bool == true)
        let turns = try #require(inner["turns"] as? [[String: Any]])
        let turn = try #require(turns.first)
        #expect(turn["role"] as? String == "user")
        let parts = try #require(turn["parts"] as? [[String: Any]])
        #expect(parts.first?["text"] as? String == "hi")
    }

    @Test("toolResponse envelope encodes functionResponses with matching id/name and arbitrary response object")
    func toolResponseEncodes() throws {
        struct Payload: Encodable {
            let success = true
            let frame = ["x": 1.0, "y": 2.0, "w": 3.0, "h": 4.0]
        }
        let env = ClientToolResponseEnvelope(
            toolResponse: ToolResponseBody(
                functionResponses: [
                    FunctionResponse(
                        id: "c2",
                        name: "point_to_element",
                        response: AnyEncodable(Payload())
                    )
                ]
            )
        )
        let dict = try roundTrip(env)
        let body = try #require(dict["toolResponse"] as? [String: Any])
        let fns = try #require(body["functionResponses"] as? [[String: Any]])
        let first = try #require(fns.first)
        #expect(first["id"] as? String == "c2")
        #expect(first["name"] as? String == "point_to_element")
        let r = try #require(first["response"] as? [String: Any])
        #expect(r["success"] as? Bool == true)
        let frame = try #require(r["frame"] as? [String: Double])
        #expect(frame["x"] == 1.0)
        #expect(frame["w"] == 3.0)
    }
}
