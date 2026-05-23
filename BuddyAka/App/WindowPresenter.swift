import AppKit
import SwiftUI

@MainActor
enum WindowPresenter {

    static func showMainWindow(using openWindow: OpenWindowAction) {
        openWindow(id: "main")
        DispatchQueue.main.async {
            NSApp.activate()
            if let window = NSApp.windows.first(where: { isMainWindow($0) }) {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    static func showSettings(using openSettings: OpenSettingsAction) {
        openSettings()
        DispatchQueue.main.async {
            NSApp.activate()
        }
    }

    private static func isMainWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.contains("main") == true
            || window.title == "BuddyAka"
    }
}
