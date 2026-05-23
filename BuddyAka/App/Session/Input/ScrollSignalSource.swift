import AppKit
import Foundation

/// Republishes global scroll-wheel events. Used to detect when the user scrolls
/// the guided element off-screen.
@MainActor
final class ScrollSignalSource {
    let events: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private var monitor: Any?

    init() {
        let (stream, cont) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.events = stream
        self.continuation = cont
        self.monitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [continuation] _ in
            continuation.yield()
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        continuation.finish()
    }
}
