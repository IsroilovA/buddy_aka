import Foundation
import Testing
@testable import BuddyAccessibility

@Suite("LayoutChangeDebouncer")
struct AXEventDebouncerTests {

    @Test("idle when nothing recorded")
    func idle() {
        let d = LayoutChangeDebouncer(window: .milliseconds(200))
        let now = ContinuousClock.Instant.now
        #expect(d.isPending == false)
        #expect(d.consume(at: now) == .idle)
    }

    @Test("single record then quiet → emits at deadline")
    func singleRecord() {
        let d = LayoutChangeDebouncer(window: .milliseconds(200))
        let t0 = ContinuousClock.Instant.now
        let deadline = d.record(at: t0)
        #expect(d.isPending)
        // Before the deadline → reschedule (defensive — caller shouldn't fire early).
        #expect(d.consume(at: t0.advanced(by: .milliseconds(100))) == .reschedule(deadline))
        // At/after the deadline → emit.
        #expect(d.consume(at: deadline) == .emit)
        #expect(d.isPending == false)
    }

    @Test("burst of records within window collapses to one emit")
    func burstCollapsesToOne() {
        let d = LayoutChangeDebouncer(window: .milliseconds(200))
        let t0 = ContinuousClock.Instant.now
        _ = d.record(at: t0)
        _ = d.record(at: t0.advanced(by: .milliseconds(50)))
        _ = d.record(at: t0.advanced(by: .milliseconds(120)))
        let lastDeadline = d.record(at: t0.advanced(by: .milliseconds(180)))

        // First timer fire (scheduled from t0) arrives at t0+200; but burst
        // extended to t0+380. Owner reschedules.
        let firstFire = t0.advanced(by: .milliseconds(200))
        #expect(d.consume(at: firstFire) == .reschedule(lastDeadline))

        // Eventually the rescheduled timer fires at lastDeadline.
        #expect(d.consume(at: lastDeadline) == .emit)
        #expect(d.isPending == false)
    }

    @Test("two separate bursts each emit once")
    func repeatedBursts() {
        let d = LayoutChangeDebouncer(window: .milliseconds(200))
        let t0 = ContinuousClock.Instant.now

        let d1 = d.record(at: t0)
        #expect(d.consume(at: d1) == .emit)

        let d2 = d.record(at: t0.advanced(by: .milliseconds(500)))
        #expect(d.consume(at: d2) == .emit)
        #expect(d.isPending == false)
    }
}
