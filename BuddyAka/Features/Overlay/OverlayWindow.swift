import AppKit
import SwiftUI

final class OverlayWindow: NSWindow {
    init<Root: View>(screen: NSScreen, rootView: Root) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        hasShadow = false
        acceptsMouseMovedEvents = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        let host = NSHostingView(rootView: rootView)
        host.frame = NSRect(origin: .zero, size: screen.frame.size)
        host.autoresizingMask = [.width, .height]
        contentView = host
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
