import Foundation
import os

public actor GeminiLiveClient {
    private let apiKey: String
    private let model: String
    private let log = Logger(subsystem: "dev.alisher.BuddyAka", category: "GeminiLive")

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var continuation: AsyncStream<LiveEvent>.Continuation?
    private let encoder = JSONEncoder()
    private(set) public var events: AsyncStream<LiveEvent>

    private var isConnected = false
    private var isStopped = false

    public init(apiKey: String, model: String = GeminiLiveWire.defaultModel) {
        self.apiKey = apiKey
        self.model = model
        var cont: AsyncStream<LiveEvent>.Continuation!
        self.events = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    public func start(config: LiveSessionConfig) async throws {
        guard !isStopped else {
            throw GeminiLiveError.setupFailed(reason: "client already stopped")
        }
        guard task == nil else {
            throw GeminiLiveError.setupFailed(reason: "already started")
        }

        var components = URLComponents(string: GeminiLiveWire.endpoint)!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw GeminiLiveError.setupFailed(reason: "couldn't build endpoint URL")
        }

        let cfg = URLSessionConfiguration.default
        let session = URLSession(configuration: cfg)
        self.session = session
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()

        // Spin up the receive loop before sending setup so we don't miss `setupComplete`.
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        let speechConfig: SpeechConfig? = config.voice.map { selection in
            SpeechConfig(voiceConfig: VoiceConfigWire(
                prebuiltVoiceConfig: PrebuiltVoiceConfigWire(voiceName: selection.voiceName)
            ))
        }

        let setup = ClientSetupEnvelope(
            setup: ClientSetup(
                model: model,
                generationConfig: GenerationConfig(
                    responseModalities: ["AUDIO"],
                    speechConfig: speechConfig
                ),
                systemInstruction: SystemInstruction(parts: [TextPart(text: config.systemInstruction)]),
                realtimeInputConfig: RealtimeInputConfig(activityHandling: "START_OF_ACTIVITY_INTERRUPTS"),
                tools: config.tools.isEmpty ? nil : config.tools,
                inputAudioTranscription: EmptyConfig(),
                outputAudioTranscription: EmptyConfig(),
                contextWindowCompression: ContextWindowCompression(
                    slidingWindow: .init(targetTokens: 32000)
                ),
                sessionResumption: SessionResumptionConfig(handle: config.resumptionHandle)
            )
        )
        do {
            try await sendJSON(setup)
        } catch {
            await teardown(emitError: .setupFailed(reason: "couldn't send setup: \(error.localizedDescription)"))
            throw GeminiLiveError.setupFailed(reason: error.localizedDescription)
        }
    }

    /// Ship a tool response back over the WebSocket. Throws if the socket is down;
    /// callers can log and continue — `receiveLoop` will surface a real disconnect
    /// via `.disconnected` separately.
    public func send(toolResponse: ToolResponse) async throws {
        let envelope = ClientToolResponseEnvelope(
            toolResponse: ToolResponseBody(
                functionResponses: [
                    FunctionResponse(
                        id: toolResponse.id,
                        name: toolResponse.name,
                        response: toolResponse.response
                    )
                ]
            )
        )
        try await sendJSON(envelope)
    }

    /// Send a chunk of 16 kHz mono Int16-LE PCM audio. No-op until `setupComplete` is received.
    public func send(pcm16kMono pcm: Data) async {
        guard isConnected, task != nil else { return }
        let envelope = ClientRealtimeAudioEnvelope(
            realtimeInput: RealtimeInputAudio(
                audio: InlineDataOut(
                    mimeType: GeminiLiveWire.inputMimeType,
                    data: pcm.base64EncodedString()
                )
            )
        )
        do {
            try await sendJSON(envelope)
        } catch {
            log.error("realtimeInput send failed: \(error.localizedDescription, privacy: .public)")
            await teardown(emitError: .disconnected(reason: error.localizedDescription))
        }
    }

    /// Send an app-generated text turn via `realtimeInput.text`. Used for Buddy
    /// control signals such as `[BUDDY_SIGNAL] target_clicked` and runtime
    /// `[BUDDY_EVENT] …` envelopes; the persona prompt knows these are not user
    /// speech. `realtimeInput` is the correct mid-session text path on the
    /// pinned model — `clientContent` is reserved for session-start seeding.
    public func sendRealtimeText(_ text: String) async {
        guard isConnected, task != nil else { return }
        let envelope = ClientRealtimeTextEnvelope(realtimeInput: RealtimeInputText(text: text))
        do {
            try await sendJSON(envelope)
        } catch {
            log.error("realtimeInput.text send failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Back-compat: route legacy callers to the realtime-text path.
    public func sendClientContentTurn(text: String) async {
        await sendRealtimeText(text)
    }

    public var lastResumptionHandle: String? { _resumptionHandle }
    private var _resumptionHandle: String?

    public func stop() async {
        await teardown(emitError: nil)
    }

    // MARK: - Private

    private func sendJSON<T: Encodable>(_ payload: T) async throws {
        guard let task else { throw GeminiLiveError.setupFailed(reason: "no socket") }
        let data = try encoder.encode(payload)
        try await task.send(.data(data))
    }

    private func receiveLoop() async {
        guard let task else { return }
        while !Task.isCancelled, !isStopped {
            do {
                let msg = try await task.receive()
                await handle(message: msg)
            } catch {
                if isStopped { return }

                // The transport error (e.g. "Socket is not connected") is almost always
                // less useful than the server's WS close frame. Prefer the close reason.
                let closeReason = task.closeReason
                    .flatMap { String(data: $0, encoding: .utf8) }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .flatMap { $0.isEmpty ? nil : $0 }

                let surface = closeReason ?? (error as NSError).localizedDescription
                let lower = surface.lowercased()
                let looksAuth = lower.contains("token")
                    || lower.contains("api key")
                    || lower.contains("apikey")
                    || lower.contains("unauth")
                    || lower.contains("forbidden")
                    || lower.contains("credential")
                    || lower.contains("permission denied")

                let mapped: GeminiLiveError
                if looksAuth {
                    mapped = .keyRejected(reason: surface)
                } else if let urlCode = (error as? URLError)?.code, closeReason == nil {
                    mapped = .network(urlCode, surface)
                } else {
                    mapped = .disconnected(reason: surface)
                }
                await teardown(emitError: mapped)
                return
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) async {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }

        let events: [LiveEvent]
        do {
            events = try ServerFrameParser.parse(data)
        } catch let err as GeminiLiveError {
            log.error("protocol parse failed: \(String(describing: err), privacy: .public)")
            await teardown(emitError: err)
            return
        } catch {
            await teardown(emitError: .protocol(reason: error.localizedDescription))
            return
        }

        for ev in events {
            if case .connected = ev { isConnected = true }
            if case .sessionResumptionUpdate(let handle, let resumable) = ev, resumable, let handle {
                _resumptionHandle = handle
            }
            continuation?.yield(ev)
        }
    }

    private func teardown(emitError: GeminiLiveError?) async {
        guard !isStopped else { return }
        isStopped = true
        isConnected = false

        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        receiveTask?.cancel()
        receiveTask = nil

        continuation?.yield(.disconnected(emitError))
        continuation?.finish()
        continuation = nil
    }
}
