import ApplicationServices
import Foundation

/// Coarse-grained AX notifications republished as Swift events.
/// Names map 1:1 to `kAX*Notification` constants — see AXObserverBridge.
public enum AXEvent: Sendable {
    case focusedElementChanged(AXElementHandle)
    case focusedWindowChanged(AXElementHandle)
    case layoutChanged
    case valueChanged(AXElementHandle)
    case windowCreated(AXElementHandle)
    case elementDestroyed
    case menuOpened
    case menuClosed
}

/// Sendable wrapper around an `AXUIElement`. CF types are reference-counted and
/// thread-safe for read; sharing across isolation domains is safe.
public struct AXElementHandle: @unchecked Sendable, Hashable {
    public let raw: AXUIElement

    public init(_ raw: AXUIElement) {
        self.raw = raw
    }

    public static func == (lhs: AXElementHandle, rhs: AXElementHandle) -> Bool {
        CFEqual(lhs.raw, rhs.raw)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(raw))
    }

    public var displayValue: String? {
        AXAttr.displayValue(raw)
    }
}

/// Production AX event source is `AXEventStream`; tests inject a fake.
public protocol AXEventSource: AnyObject, Sendable {
    var events: AsyncStream<AXEvent> { get }
    @MainActor func rebind(to pid: pid_t) throws
    @MainActor func stop()
}
