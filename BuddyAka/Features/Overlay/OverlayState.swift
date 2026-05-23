import AppKit
import Observation

@MainActor
@Observable
final class OverlayState {
    private(set) var visible: Bool = false
    private(set) var cursorPosition: CGPoint = .zero {
        didSet { recomputeTargetScreen() }
    }
    private(set) var targetScreenID: CGDirectDisplayID?
    private(set) var haloTargetFrame: CGRect? = nil

    init() {
        self.targetScreenID = ScreenGeometry.displayID(containing: cursorPosition)
    }

    func show() {
        let mouse = NSEvent.mouseLocation
        if cursorPosition != mouse { cursorPosition = mouse }
        if !visible { visible = true }
    }

    func hide() {
        if visible { visible = false }
        if haloTargetFrame != nil { haloTargetFrame = nil }
    }

    func move(to point: CGPoint) {
        guard point != cursorPosition else { return }
        cursorPosition = point
    }

    func setHaloTarget(_ frame: CGRect?) {
        guard frame != haloTargetFrame else { return }
        haloTargetFrame = frame
    }

    func pointAt(_ frame: CGRect) {
        show()
        move(to: CGPoint(x: frame.midX, y: frame.midY))
        setHaloTarget(frame)
    }

    func refreshTargetScreen() {
        recomputeTargetScreen()
    }

    private func recomputeTargetScreen() {
        let id = ScreenGeometry.displayID(containing: cursorPosition)
        if id != targetScreenID { targetScreenID = id }
    }
}
