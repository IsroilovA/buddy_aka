import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var openWindow: OpenWindowAction?

    func bind(openWindow: OpenWindowAction) {
        self.openWindow = openWindow
    }

    nonisolated func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Task { @MainActor in
                NSApp.activate()
                self.openWindow?(id: "main")
            }
        }
        return true
    }
}
