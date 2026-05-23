import ApplicationServices
import Dispatch
import Foundation

// Wraps one AXObserver bound to one pid. Yields events through the parent
// stream's continuation. All mutation happens on the main thread:
//   - init is called from @MainActor AXEventStream
//   - the C callback fires on the run loop the observer source is attached to
//     (we add it to CFRunLoopGetMain())
//   - the layout-changed debouncer uses a DispatchSourceTimer on .main
//
// Marked @unchecked Sendable so @MainActor AXEventStream can own it; the
// single-thread invariant above is what actually makes that safe.
final class AXObserverBridge: @unchecked Sendable {
    private let observer: AXObserver
    private let runLoopSource: CFRunLoopSource
    private let target: AXUIElement
    private var registered: [String]
    private let continuation: AsyncStream<AXEvent>.Continuation
    private let debouncer = LayoutChangeDebouncer()
    private var debounceTimer: DispatchSourceTimer?
    private var isTornDown = false

    init(pid: pid_t, continuation: AsyncStream<AXEvent>.Continuation) throws {
        var rawObserver: AXObserver?
        let createResult = AXObserverCreate(pid, _axObserverCallback, &rawObserver)
        guard createResult == .success, let obs = rawObserver else {
            throw AXEventStream.Error.axError(createResult)
        }
        self.observer = obs
        self.runLoopSource = AXObserverGetRunLoopSource(obs)
        self.target = AXUIElementCreateApplication(pid)
        self.continuation = continuation
        self.registered = []

        // The six notifications the session machine cares about, per arch §6.
        // We attempt all; some apps don't support every notification (no menus,
        // etc.) — tolerate per-notification failures so a partial subscription
        // is still useful.
        let names: [String] = [
            kAXFocusedUIElementChangedNotification,
            kAXFocusedWindowChangedNotification,
            kAXLayoutChangedNotification,
            kAXWindowCreatedNotification,
            kAXMenuOpenedNotification,
            kAXMenuClosedNotification,
        ]
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var added: [String] = []
        for name in names {
            let err = AXObserverAddNotification(obs, target, name as CFString, refcon)
            if err == .success { added.append(name) }
        }
        self.registered = added

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            runLoopSource,
            .defaultMode
        )
    }

    /// Must be called from the @MainActor owner BEFORE dropping the last
    /// reference to this bridge. Removes all registered AX notifications
    /// synchronously so no in-flight C callback can dereference a dangling
    /// refcon. Idempotent.
    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        debounceTimer?.cancel()
        debounceTimer = nil
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        for name in registered {
            AXObserverRemoveNotification(observer, target, name as CFString)
        }
        registered.removeAll()
    }

    deinit {
        // Defensive fallback for callers that forgot to invoke tearDown().
        // Doing the C cleanup ONLY in deinit was the cause of an EXC_BAD_ACCESS
        // when a pending main-runloop callback raced ARC release order.
        debounceTimer?.cancel()
        if !isTornDown {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        for name in registered {
            AXObserverRemoveNotification(observer, target, name as CFString)
        }
    }

    fileprivate func handle(notification: CFString, element: AXUIElement) {
        guard !isTornDown else { return }
        let name = notification as String
        switch name {
        case kAXFocusedUIElementChangedNotification:
            continuation.yield(.focusedElementChanged(AXElementHandle(element)))
        case kAXFocusedWindowChangedNotification:
            continuation.yield(.focusedWindowChanged(AXElementHandle(element)))
        case kAXLayoutChangedNotification:
            scheduleLayoutChangedEmit()
        case kAXValueChangedNotification:
            continuation.yield(.valueChanged(AXElementHandle(element)))
        case kAXWindowCreatedNotification:
            continuation.yield(.windowCreated(AXElementHandle(element)))
        case kAXUIElementDestroyedNotification:
            continuation.yield(.elementDestroyed)
        case kAXMenuOpenedNotification:
            continuation.yield(.menuOpened)
        case kAXMenuClosedNotification:
            continuation.yield(.menuClosed)
        default:
            break
        }
    }

    // Pragmatic GCD exception (project convention is "no GCD"): a 200 ms debounce
    // inside a C-callback context using Task.sleep is genuinely awkward, and this
    // is a 50-line internal of the package — not user-facing concurrency. The
    // pure decision logic lives in LayoutChangeDebouncer, which IS unit-tested.
    private func scheduleLayoutChangedEmit() {
        _ = debouncer.record(at: .now)
        debounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(200))
        timer.setEventHandler { [weak self] in
            self?.fireDebouncedTimer()
        }
        timer.resume()
        debounceTimer = timer
    }

    private func fireDebouncedTimer() {
        debounceTimer = nil
        if case .emit = debouncer.consume(at: .now) {
            continuation.yield(.layoutChanged)
        }
    }
}

// Top-level @convention(c)-compatible trampoline. Recovers the owning bridge
// from refcon. Runs on the main thread (the observer source is attached to
// CFRunLoopGetMain()).
private func _axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let bridge = Unmanaged<AXObserverBridge>.fromOpaque(refcon).takeUnretainedValue()
    bridge.handle(notification: notification, element: element)
}
