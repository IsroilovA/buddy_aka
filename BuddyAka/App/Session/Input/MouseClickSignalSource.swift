import AppKit
import Foundation

/// Republishes global left-mouse-down clicks delivered to other applications.
/// The overlay ignores mouse events, so clicks on the highlighted target still
/// reach the target app and appear here while BuddyAka is guiding.
@MainActor
final class MouseClickSignalSource {
    let events: AsyncStream<CGPoint>
    private let continuation: AsyncStream<CGPoint>.Continuation
    private var monitor: Any?

    init() {
        let (stream, cont) = AsyncStream<CGPoint>.makeStream(bufferingPolicy: .bufferingNewest(64))
        self.events = stream
        self.continuation = cont
        self.monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [continuation] _ in
            continuation.yield(NSEvent.mouseLocation)
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
