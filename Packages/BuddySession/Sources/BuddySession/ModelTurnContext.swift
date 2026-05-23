import Foundation

/// Owns the buddy-signal lifecycle relative to the model's speaking turn.
///
/// - Drops `idleTimeout` if the model is mid-speech (the user wasn't idle —
///   they were listening).
/// - Coalesces `screenChanged` (level signal) to the latest; edge signals are
///   appended with a consecutive-identical defense.
/// - Bounds the pending buffer at `capacity` (drop-oldest on overflow).
/// - Formats the consolidated `[BUDDY_SIGNALS]` envelope when draining on
///   `turnComplete`.
public struct ModelTurnContext: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case idle
        case speaking
    }

    public enum Decision: Sendable, Equatable {
        case sendNow(String)
        case buffered
        case dropped(reason: DropReason)
    }

    public enum DropReason: String, Sendable, Equatable {
        case modelSpeaking = "model_speaking"
        case consecutiveDuplicate = "consecutive_dup"
        case bufferOverflow = "buffer_overflow"
    }

    public let capacity: Int
    private(set) public var phase: Phase = .idle
    private var pending: [BuddySignal] = []

    public init(capacity: Int = 16) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public mutating func phaseChanged(to phase: Phase) {
        self.phase = phase
    }

    public mutating func enqueue(_ signal: BuddySignal) -> Decision {
        if signal == .idleTimeout && phase == .speaking {
            return .dropped(reason: .modelSpeaking)
        }

        if phase == .idle {
            return .sendNow(Self.formatEnvelope([signal]))
        }

        switch signal {
        case .screenChanged:
            pending.removeAll { $0 == .screenChanged }
        default:
            if pending.last == signal { return .dropped(reason: .consecutiveDuplicate) }
        }

        pending.append(signal)

        var overflowed = false
        while pending.count > capacity {
            pending.removeFirst()
            overflowed = true
        }
        return overflowed ? .dropped(reason: .bufferOverflow) : .buffered
    }

    public mutating func drainOnTurnComplete() -> String? {
        phase = .idle
        guard !pending.isEmpty else { return nil }
        let payload = Self.formatEnvelope(pending)
        pending.removeAll()
        return payload
    }

    public var pendingForInspection: [BuddySignal] { pending }

    private static func formatEnvelope(_ signals: [BuddySignal]) -> String {
        let names = signals.map(\.rawValue).joined(separator: ", ")
        return "[BUDDY_SIGNALS] \(names)"
    }
}
