import Foundation

/// Collapses bursts of `kAXLayoutChangedNotification` into one event after a
/// quiet window. Pure decision logic — does not own the clock or the timer.
/// The owner (`AXObserverBridge`) records each incoming signal and consults
/// `consume(at:)` from its scheduled timer.
///
/// Architecture §6 calls for a 200 ms window. Layout-changed alone arrives
/// during animations and scrolls and would otherwise flood Gemini.
final class LayoutChangeDebouncer {
    enum ConsumeResult: Equatable {
        case emit
        case reschedule(ContinuousClock.Instant)
        case idle
    }

    let window: Duration
    private var pendingFire: ContinuousClock.Instant?

    init(window: Duration = .milliseconds(200)) {
        self.window = window
    }

    /// Record a new burst sample. Returns the deadline at which the owner
    /// should arm (or re-arm) its timer.
    func record(at now: ContinuousClock.Instant) -> ContinuousClock.Instant {
        let deadline = now.advanced(by: window)
        pendingFire = deadline
        return deadline
    }

    /// Called when the timer fires. If `now` reached the deadline, returns
    /// `.emit` and clears state. If the burst extended past it, returns
    /// `.reschedule(newDeadline)`. `.idle` is defensive — shouldn't happen
    /// unless a stale fire arrives after the burst was already consumed.
    func consume(at now: ContinuousClock.Instant) -> ConsumeResult {
        guard let fire = pendingFire else { return .idle }
        if now >= fire {
            pendingFire = nil
            return .emit
        }
        return .reschedule(fire)
    }

    var isPending: Bool { pendingFire != nil }
}
