@preconcurrency import AVFoundation
import Foundation

public enum AudioFormats {
    public static let captureSampleRate: Double = 16_000
    public static let playbackSampleRate: Double = 24_000

    /// 16 kHz mono Int16 little-endian — Gemini Live's required input format.
    public static let capturePCM: AVAudioFormat = {
        guard let fmt = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: captureSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            fatalError("BuddyVoice: failed to construct 16kHz Int16 capture format")
        }
        return fmt
    }()

    /// 24 kHz mono Int16 — Gemini Live's audio output format on the wire.
    public static let playbackPCMInt16: AVAudioFormat = {
        guard let fmt = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: playbackSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            fatalError("BuddyVoice: failed to construct 24kHz Int16 playback format")
        }
        return fmt
    }()

}
