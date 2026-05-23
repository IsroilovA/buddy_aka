import ApplicationServices
import Foundation

/// Republishes AX notifications for a single target pid as an `AsyncStream`.
/// One observer at a time; call `rebind(to:)` to follow a different app.
///
/// Pid-switching lives in the coordinator (`SessionCoordinator` observes
/// `NSWorkspace.didActivateApplicationNotification` and calls `rebind`) so
/// this package stays AppKit-free for its library target.
@MainActor
public final class AXEventStream: AXEventSource {
    public enum Error: Swift.Error, Sendable {
        case accessibilityNotTrusted
        case axError(AXError)
    }

    public let events: AsyncStream<AXEvent>
    private let continuation: AsyncStream<AXEvent>.Continuation
    private var bridge: AXObserverBridge?

    public init(initialPid: pid_t) throws {
        guard AXIsProcessTrusted() else {
            throw Error.accessibilityNotTrusted
        }
        let (stream, cont) = AsyncStream<AXEvent>.makeStream(bufferingPolicy: .bufferingNewest(256))
        self.events = stream
        self.continuation = cont
        self.bridge = try AXObserverBridge(pid: initialPid, continuation: cont)
    }

    /// Tear down the current bridge and build a new one bound to `pid`.
    /// Atomic from the consumer's POV: the continuation is shared, so no
    /// events are lost mid-rebind beyond what's actually missed by the OS.
    public func rebind(to pid: pid_t) throws {
        guard AXIsProcessTrusted() else {
            bridge?.tearDown()
            bridge = nil
            throw Error.accessibilityNotTrusted
        }
        bridge?.tearDown()
        bridge = nil
        bridge = try AXObserverBridge(pid: pid, continuation: continuation)
    }

    public func stop() {
        bridge?.tearDown()
        bridge = nil
        continuation.finish()
    }
}
