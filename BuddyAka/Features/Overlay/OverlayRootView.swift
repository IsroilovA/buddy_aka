import SwiftUI
import AppKit

struct OverlayRootView: View {
    let screen: NSScreen
    @Environment(OverlayState.self) private var overlay

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            if overlay.visible,
               overlay.targetScreenID == ScreenGeometry.displayID(of: screen) {

                if let frame = overlay.haloTargetFrame {
                    let center = ScreenGeometry.localTopLeftPoint(
                        CGPoint(x: frame.midX, y: frame.midY),
                        in: screen
                    )
                    HaloView(diameter: max(frame.width, frame.height) + 16)
                        .position(x: center.x, y: center.y)
                        .transition(.opacity)
                }

                let cursor = ScreenGeometry.localTopLeftPoint(overlay.cursorPosition, in: screen)
                BuddyView()
                    .position(x: cursor.x + 10, y: cursor.y + 10)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: overlay.cursorPosition)
        .animation(.easeOut(duration: 0.18), value: overlay.visible)
        .allowsHitTesting(false)
    }
}
