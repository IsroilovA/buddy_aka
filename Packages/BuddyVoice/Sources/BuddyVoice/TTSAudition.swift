@preconcurrency import AVFoundation
import Foundation
import os

/// One-shot TTS audition for the voice picker. Decoupled from `GeminiLiveClient`:
/// hits Gemini's REST `generateContent` endpoint against a TTS model and plays the
/// returned PCM through a self-contained `AVAudioEngine`, so it can run alongside a
/// live Buddy session without contending for the shared playback pipeline.
@MainActor
public final class TTSAudition {
    public enum AuditionError: LocalizedError {
        case missingAudio
        case http(status: Int, body: String)
        case decode(String)

        public var errorDescription: String? {
            switch self {
            case .missingAudio: return "Gemini returned no audio for the requested voice."
            case .http(let status, let body): return "TTS request failed (\(status)): \(body)"
            case .decode(let m): return "Couldn't decode TTS response: \(m)"
            }
        }
    }

    private let apiKey: String
    private let model: String
    private let urlSession: URLSession
    private let log = Logger(subsystem: "dev.alisher.BuddyAka", category: "TTSAudition")

    // Keyed on (voiceName, text) so swapping the audition's language replays in the
    // new language instead of returning the previously-cached voice line.
    private struct SampleKey: Hashable { let voiceName: String; let text: String }
    private var cache: [SampleKey: Data] = [:]
    private var fetches: [SampleKey: Task<Data, Error>] = [:]

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var engineConfigured = false
    private var engineStarted = false

    /// Tracks whether the user has cancelled the in-flight playback so an arriving
    /// `scheduleBuffer` completion knows not to flip "playing" back off after the
    /// new audition has already started.
    private var currentPlaybackToken = 0
    public private(set) var isPlaying = false

    public init(
        apiKey: String,
        model: String = "models/gemini-2.5-flash-preview-tts",
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.urlSession = urlSession
    }

    /// Fetch (or reuse cached) PCM for `voiceName` and play it once. Calling again
    /// while audio is in flight stops the current sample and starts the new one.
    public func sample(voiceName: String, text: String = "Hi, I'm Buddy.") async throws {
        let pcm = try await pcm(forVoice: voiceName, text: text)
        try play(pcm: pcm)
    }

    public func stop() {
        currentPlaybackToken &+= 1
        isPlaying = false
        guard engineStarted else { return }
        playerNode.stop()
        playerNode.reset()
        if engine.isRunning {
            playerNode.play()
        }
    }

    // MARK: - Fetch + cache

    private func pcm(forVoice voiceName: String, text: String) async throws -> Data {
        let key = SampleKey(voiceName: voiceName, text: text)
        if let cached = cache[key] { return cached }
        if let inflight = fetches[key] { return try await inflight.value }

        let task = Task<Data, Error> { [apiKey, model, urlSession] in
            try await Self.fetch(
                apiKey: apiKey,
                model: model,
                voiceName: voiceName,
                text: text,
                urlSession: urlSession
            )
        }
        fetches[key] = task
        defer { fetches[key] = nil }

        let data = try await task.value
        cache[key] = data
        return data
    }

    private static func fetch(
        apiKey: String,
        model: String,
        voiceName: String,
        text: String,
        urlSession: URLSession
    ) async throws -> Data {
        // Model path may carry a "models/" prefix (matching Live convention); strip
        // it so we don't end up with "/models/models/...".
        let modelPath = model.hasPrefix("models/") ? model : "models/\(model)"
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/\(modelPath):generateContent")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw AuditionError.decode("couldn't build TTS URL")
        }

        let body: [String: Any] = [
            "contents": [["parts": [["text": text]]]],
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": [
                    "voiceConfig": [
                        "prebuiltVoiceConfig": [
                            "voiceName": voiceName
                        ]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuditionError.decode("response was not HTTPURLResponse")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
            throw AuditionError.http(status: http.statusCode, body: bodyText)
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else {
            throw AuditionError.decode("malformed candidates payload")
        }

        for part in parts {
            if let inline = part["inlineData"] as? [String: Any],
               let b64 = inline["data"] as? String,
               let pcm = Data(base64Encoded: b64) {
                return pcm
            }
        }
        throw AuditionError.missingAudio
    }

    // MARK: - Playback

    private func play(pcm: Data) throws {
        guard !pcm.isEmpty else { return }
        try ensureEngineStarted()
        guard let target = targetFormat, let converter else { return }

        // New playback supersedes any in-flight one.
        currentPlaybackToken &+= 1
        let token = currentPlaybackToken

        if isPlaying {
            playerNode.stop()
            playerNode.reset()
            playerNode.play()
        }

        let inputFrames = AVAudioFrameCount(pcm.count / MemoryLayout<Int16>.size)
        guard inputFrames > 0,
              let intBuf = AVAudioPCMBuffer(pcmFormat: AudioFormats.playbackPCMInt16, frameCapacity: inputFrames)
        else { return }
        intBuf.frameLength = inputFrames
        pcm.withUnsafeBytes { raw in
            guard let src = raw.baseAddress, let dst = intBuf.int16ChannelData?[0] else { return }
            memcpy(dst, src, Int(inputFrames) * MemoryLayout<Int16>.size)
        }

        let ratio = target.sampleRate / AudioFormats.playbackSampleRate
        let outCapacity = AVAudioFrameCount(Double(inputFrames) * ratio + 1024)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCapacity) else { return }

        var err: NSError?
        let provider = AuditionInputBuffer(intBuf)
        let status = converter.convert(to: outBuf, error: &err) { _, outStatus in
            provider.next(outStatus: outStatus)
        }
        guard status != .error, outBuf.frameLength > 0 else { return }

        isPlaying = true
        playerNode.scheduleBuffer(outBuf) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.currentPlaybackToken == token {
                    self.isPlaying = false
                }
            }
        }
    }

    private func ensureEngineStarted() throws {
        if !engineConfigured {
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
            engineConfigured = true
        }
        if !engineStarted {
            engine.prepare()
            try engine.start()
            playerNode.play()
            let target = playerNode.outputFormat(forBus: 0)
            targetFormat = target
            converter = AVAudioConverter(from: AudioFormats.playbackPCMInt16, to: target)
            engineStarted = true
        }
    }
}

private final class AuditionInputBuffer: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            outStatus.pointee = .noDataNow
            return nil
        }
        self.buffer = nil
        outStatus.pointee = .haveData
        return buffer
    }
}
