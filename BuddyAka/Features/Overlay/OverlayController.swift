import AppKit
import SwiftUI
import Observation

@MainActor
final class OverlayController {
    private let state: OverlayState
    private let settings: BuddySettings
    private var windows: [(screen: NSScreen, window: OverlayWindow)] = []
    @ObservationIgnored private nonisolated(unsafe) var screenObserver: NSObjectProtocol?

    init(state: OverlayState, settings: BuddySettings) {
        self.state = state
        self.settings = settings
        rebuildWindows()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenParametersChange()
            }
        }
        startObserving()
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    private func rebuildWindows() {
        for entry in windows {
            entry.window.orderOut(nil)
            entry.window.close()
        }
        windows = NSScreen.screens.map { screen in
            let root = OverlayRootView(screen: screen)
                .environment(state)
                .environment(settings)
            return (screen, OverlayWindow(screen: screen, rootView: root))
        }
    }

    private func handleScreenParametersChange() {
        let currentIDs = Set(NSScreen.screens.compactMap { ScreenGeometry.displayID(of: $0) })
        let knownIDs = Set(windows.compactMap { ScreenGeometry.displayID(of: $0.screen) })
        if currentIDs == knownIDs {
            var updated: [(screen: NSScreen, window: OverlayWindow)] = []
            updated.reserveCapacity(windows.count)
            for entry in windows {
                if let id = ScreenGeometry.displayID(of: entry.screen),
                   let screen = NSScreen.screens.first(where: { ScreenGeometry.displayID(of: $0) == id }) {
                    entry.window.setFrame(screen.frame, display: true)
                    updated.append((screen, entry.window))
                } else {
                    updated.append(entry)
                }
            }
            windows = updated
        } else {
            rebuildWindows()
        }
        state.refreshTargetScreen()
        apply()
    }

    private func startObserving() {
        withObservationTracking {
            _ = state.visible
            _ = state.targetScreenID
        } onChange: {
            Task { @MainActor [weak self] in
                self?.apply()
                self?.startObserving()
            }
        }
    }

    private func apply() {
        guard state.visible else {
            for entry in windows { entry.window.orderOut(nil) }
            return
        }
        let targetID = state.targetScreenID
        for entry in windows {
            if ScreenGeometry.displayID(of: entry.screen) == targetID {
                entry.window.orderFrontRegardless()
            } else {
                entry.window.orderOut(nil)
            }
        }
    }
}

enum ScreenGeometry {
    static var primary: NSScreen {
        NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    static func screen(containing global: CGPoint) -> NSScreen {
        NSScreen.screens.first(where: { $0.frame.contains(global) }) ?? primary
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func displayID(containing global: CGPoint) -> CGDirectDisplayID? {
        displayID(of: screen(containing: global))
    }

    static func localTopLeftPoint(_ global: CGPoint, in screen: NSScreen) -> CGPoint {
        return CGPoint(
            x: global.x - screen.frame.minX,
            y: screen.frame.maxY - global.y
        )
    }

    // AX returns positions in a top-left-origin coordinate space anchored at the
    // primary screen, Y growing downward. NSScreen (and NSEvent.mouseLocation) use
    // bottom-left-origin Cocoa coordinates. Flip Y against the primary screen.
    static func axPointToCocoa(_ p: CGPoint) -> CGPoint {
        let primaryMaxY = primary.frame.maxY
        return CGPoint(x: p.x, y: primaryMaxY - p.y)
    }

    static func axRectToCocoa(_ r: CGRect) -> CGRect {
        let primaryMaxY = primary.frame.maxY
        return CGRect(
            x: r.origin.x,
            y: primaryMaxY - r.origin.y - r.size.height,
            width: r.size.width,
            height: r.size.height
        )
    }
}
