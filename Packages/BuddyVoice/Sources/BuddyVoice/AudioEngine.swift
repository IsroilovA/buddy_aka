@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import os

/// Capture uses `AVCaptureSession` (CoreMedia / `CMSampleBuffer` pipeline) because
/// `AVAudioEngine`'s input-tap path is broken in macOS 26 Tahoe — the IO render thread
/// overloads and triggers `dispatch_assert_queue_fail` inside `HALC_ProxyIOContext`.
/// `AVCaptureSession` is a different code path that doesn't go through that machinery.
///
/// Playback stays on `AVAudioEngine` with `AVAudioPlayerNode` — that side of the engine
/// works fine; only the input render loop is affected.
@MainActor
public final class AudioEngine {
    // Capture: AVCaptureSession side.
    private let captureSession = AVCaptureSession()
    private let captureDelegate = AudioCaptureDelegate()
    private let captureQueue = DispatchQueue(label: "dev.alisher.BuddyAka.audioCapture", qos: .userInteractive)
    private var captureInput: AVCaptureDeviceInput?
    private var captureOutput: AVCaptureAudioDataOutput?
    private var captureConfigured = false
    private var captureStarted = false

    // Playback: AVAudioEngine side. Starts lazily on first received chunk.
    private let playbackEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var playbackConverter: AVAudioConverter?
    private var playbackTargetFormat: AVAudioFormat?
    private var playbackConfigured = false
    private var playbackStarted = false
    private let log = Logger(subsystem: "dev.alisher.BuddyAka", category: "AudioEngine")

    /// Half-duplex gate. While playback is queued, the capture delegate drops mic frames so
    /// Gemini's server-side VAD doesn't hear its own voice and try to interrupt itself.
    private let pendingPlaybackChunks = OSAllocatedUnfairLock<Int>(initialState: 0)

    public init() {}

    public func start(onChunk: @escaping @Sendable (Data) -> Void) throws {
        guard !captureStarted else { return }

        if !captureConfigured {
            try configureCapture(onChunk: onChunk)
        } else {
            captureDelegate.configure(
                onChunk: onChunk,
                pendingPlayback: pendingPlaybackChunks
            )
        }

        // AVCaptureSession.startRunning is blocking; run on a background queue to avoid
        // stalling the caller. start(onChunk:) returns once the session has been told to start.
        captureQueue.async { [captureSession] in
            captureSession.startRunning()
        }
        captureStarted = true
    }

    private func configureCapture(onChunk: @escaping @Sendable (Data) -> Void) throws {
        guard !captureConfigured else { return }

        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw GeminiLiveError.audioSetupFailed(reason: "no default audio capture device")
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw GeminiLiveError.audioSetupFailed(reason: "AVCaptureDeviceInput: \(error.localizedDescription)")
        }

        captureSession.beginConfiguration()
        guard captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            throw GeminiLiveError.audioSetupFailed(reason: "can't add capture input")
        }
        captureSession.addInput(input)
        captureInput = input

        let output = AVCaptureAudioDataOutput()
        // Ask AVCaptureSession to deliver samples already in Gemini's required format,
        // skipping the AVAudioConverter step on the hot path.
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: AudioFormats.captureSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        captureDelegate.configure(
            onChunk: onChunk,
            pendingPlayback: pendingPlaybackChunks
        )
        output.setSampleBufferDelegate(captureDelegate, queue: captureQueue)

        guard captureSession.canAddOutput(output) else {
            captureSession.commitConfiguration()
            throw GeminiLiveError.audioSetupFailed(reason: "can't add capture output")
        }
        captureSession.addOutput(output)
        captureOutput = output
        captureSession.commitConfiguration()
        captureConfigured = true
    }

    public func play(pcm24kMono: Data) {
        guard !pcm24kMono.isEmpty else { return }
        do { try ensurePlaybackStarted() } catch {
            log.error("playback setup failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let target = playbackTargetFormat,
              let converter = playbackConverter else { return }

        let inputFrames = AVAudioFrameCount(pcm24kMono.count / MemoryLayout<Int16>.size)
        guard inputFrames > 0,
              let intBuf = AVAudioPCMBuffer(pcmFormat: AudioFormats.playbackPCMInt16, frameCapacity: inputFrames)
        else { return }
        intBuf.frameLength = inputFrames
        pcm24kMono.withUnsafeBytes { raw in
            guard let src = raw.baseAddress, let dst = intBuf.int16ChannelData?[0] else { return }
            memcpy(dst, src, Int(inputFrames) * MemoryLayout<Int16>.size)
        }

        let ratio = target.sampleRate / AudioFormats.playbackSampleRate
        let outFrameCapacity = AVAudioFrameCount(Double(inputFrames) * ratio + 1024)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outFrameCapacity) else { return }

        var error: NSError?
        let inputProvider = SingleUseAudioBuffer(intBuf)
        let status = converter.convert(to: outBuf, error: &error) { _, outStatus in
            inputProvider.next(outStatus: outStatus)
        }
        guard status != .error, outBuf.frameLength > 0 else { return }

        let pending = pendingPlaybackChunks
        pending.withLock { $0 += 1 }
        playerNode.scheduleBuffer(outBuf) {
            pending.withLock { $0 = max(0, $0 - 1) }
        }
    }

    public func cancelPlayback() {
        pendingPlaybackChunks.withLock { $0 = 0 }
        guard playbackStarted else { return }
        playerNode.stop()
        playerNode.reset()
        if playbackEngine.isRunning {
            playerNode.play()
        }
    }

    private func ensurePlaybackStarted() throws {
        guard !playbackStarted else { return }
        if !playbackConfigured {
            playbackEngine.attach(playerNode)
            playbackEngine.connect(playerNode, to: playbackEngine.mainMixerNode, format: nil)
            playbackConfigured = true
        }
        playbackEngine.prepare()
        try playbackEngine.start()
        playerNode.play()

        let target = playerNode.outputFormat(forBus: 0)
        playbackTargetFormat = target
        playbackConverter = AVAudioConverter(from: AudioFormats.playbackPCMInt16, to: target)
        playbackStarted = true
    }

    public func stop() {
        if captureStarted {
            captureQueue.async { [captureSession] in
                captureSession.stopRunning()
            }
            captureStarted = false
        }
        if playbackStarted {
            playerNode.stop()
            playbackEngine.stop()
            playbackConverter = nil
            playbackTargetFormat = nil
            playbackStarted = false
        }
        pendingPlaybackChunks.withLock { $0 = 0 }
    }
}

private final class SingleUseAudioBuffer: @unchecked Sendable {
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

/// Receives `CMSampleBuffer` from AVCaptureSession on a background dispatch queue. Pulls
/// out the raw PCM bytes (already in 16 kHz mono Int16-LE by AVCaptureAudioDataOutput's
/// audioSettings) and forwards them to the chunk handler.
private final class AudioCaptureDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private var onChunk: (@Sendable (Data) -> Void)?
    private var pendingPlayback: OSAllocatedUnfairLock<Int>?

    func configure(
        onChunk: @escaping @Sendable (Data) -> Void,
        pendingPlayback: OSAllocatedUnfairLock<Int>
    ) {
        self.onChunk = onChunk
        self.pendingPlayback = pendingPlayback
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Half-duplex gate.
        if let p = pendingPlayback, p.withLock({ $0 }) > 0 { return }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard status == noErr, let ptr = dataPointer, totalLength > 0 else { return }

        let data = Data(bytes: ptr, count: totalLength)
        onChunk?(data)
    }
}
