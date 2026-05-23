import Foundation
import Testing
@testable import BuddyVoice

@Suite("Server frame parsing → LiveEvent")
struct LiveEventDecodingTests {

    @Test("setupComplete yields .connected")
    func setupComplete() throws {
        let json = #"{"setupComplete":{}}"#
        let events = try ServerFrameParser.parse(Data(json.utf8))
        #expect(events == [.connected])
    }

    @Test("serverContent with inlineData audio yields .audioChunk with decoded PCM")
    func audioChunkDecoded() throws {
        let pcm = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let b64 = pcm.base64EncodedString()
        let json = """
        {"serverContent":{"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm;rate=24000","data":"\(b64)"}}]}}}
        """
        let events = try ServerFrameParser.parse(Data(json.utf8))
        #expect(events == [.audioChunk(pcm)])
    }

    @Test("turnComplete yields .turnComplete")
    func turnComplete() throws {
        let json = #"{"serverContent":{"turnComplete":true}}"#
        let events = try ServerFrameParser.parse(Data(json.utf8))
        #expect(events == [.turnComplete])
    }

    @Test("interrupted flag yields .interrupted")
    func interruptedFlagDecodes() throws {
        let json = #"{"serverContent":{"interrupted":true}}"#
        let events = try ServerFrameParser.parse(Data(json.utf8))
        #expect(events == [.interrupted])
    }

    @Test("interrupted is yielded before turnComplete in the same frame")
    func interruptedBeforeTurnComplete() throws {
        let json = #"{"serverContent":{"interrupted":true,"turnComplete":true}}"#
        let events = try ServerFrameParser.parse(Data(json.utf8))
        #expect(events == [.interrupted, .turnComplete])
    }

    @Test("input/output transcriptions yield transcript events")
    func transcriptions() throws {
        let json = """
        {"serverContent":{"inputTranscription":{"text":"hello"},"outputTranscription":{"text":"hi back"}}}
        """
        let events = try ServerFrameParser.parse(Data(json.utf8))
        #expect(events == [.inputTranscript("hello"), .outputTranscript("hi back")])
    }

    @Test("toolCall preserves args as raw JSON bytes")
    func toolCallParses() throws {
        let json = """
        {"toolCall":{"functionCalls":[{"name":"point_to_element","id":"call_1","args":{"element_id":"e_42","narration":"the blue button"}}]}}
        """
        let events = try ServerFrameParser.parse(Data(json.utf8))
        guard case .toolCall(let call) = events.first else {
            Issue.record("expected toolCall, got \(events)")
            return
        }
        #expect(call.name == "point_to_element")
        #expect(call.id == "call_1")
        let parsed = try #require(
            try JSONSerialization.jsonObject(with: call.argsJSON) as? [String: Any]
        )
        #expect(parsed["element_id"] as? String == "e_42")
        #expect(parsed["narration"] as? String == "the blue button")
    }

    @Test("malformed JSON throws .protocol")
    func malformedThrows() throws {
        let json = "{not json"
        #expect(throws: GeminiLiveError.self) {
            _ = try ServerFrameParser.parse(Data(json.utf8))
        }
    }

    @Test("goAway frame yields an event")
    func goAway() throws {
        let json = #"{"goAway":{"timeLeft":"5s"}}"#
        let events = try ServerFrameParser.parse(Data(json.utf8))
        #expect(events == [.goAway(reason: "5s")])
    }

    @Test("multiple parts in one frame emit multiple audio events in order")
    func multipleAudioParts() throws {
        let a = Data([0x01, 0x02])
        let b = Data([0x03, 0x04])
        let json = """
        {"serverContent":{"modelTurn":{"parts":[
            {"inlineData":{"mimeType":"audio/pcm;rate=24000","data":"\(a.base64EncodedString())"}},
            {"inlineData":{"mimeType":"audio/pcm;rate=24000","data":"\(b.base64EncodedString())"}}
        ]},"turnComplete":true}}
        """
        let events = try ServerFrameParser.parse(Data(json.utf8))
        #expect(events == [.audioChunk(a), .audioChunk(b), .turnComplete])
    }
}
