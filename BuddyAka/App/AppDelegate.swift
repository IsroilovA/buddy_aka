import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var openWindow: OpenWindowAction?
    private var openSettings: OpenSettingsAction?
    private var session: SessionCoordinator?
    private var onboarding: OnboardingState?
    private var settingsRoute: SettingsRoute?
    private var shortcutRegistered = false

    func bind(
        openWindow: OpenWindowAction,
        openSettings: OpenSettingsAction,
        session: SessionCoordinator,
        onboarding: OnboardingState,
        settingsRoute: SettingsRoute
    ) {
        self.openWindow = openWindow
        self.openSettings = openSettings
        self.session = session
        self.onboarding = onboarding
        self.settingsRoute = settingsRoute

        guard !shortcutRegistered else { return }
        shortcutRegistered = true

        KeyboardShortcuts.onKeyUp(for: .toggleBuddy) { [weak self] in
            MainActor.assumeIsolated {
                self?.toggleSession()
            }
        }
    }

    nonisolated func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Task { @MainActor in
                if let openWindow = self.openWindow {
                    WindowPresenter.showMainWindow(using: openWindow)
                }
            }
        }
        return true
    }

    private func toggleSession() {
        guard let session, let openWindow else { return }
        if session.isActive {
            session.stop()
        } else {
            session.start(
                routing: SessionStartRouting(
                    onMissingPermissions: { [weak self] in
                        self?.onboarding?.blockForPermissions()
                        if let ow = self?.openWindow {
                            WindowPresenter.showMainWindow(using: ow)
                        }
                    },
                    onMissingAPIKey: { [weak self] in
                        self?.settingsRoute?.selectedTab = .apiKey
                        if let os = self?.openSettings {
                            WindowPresenter.showSettings(using: os)
                        }
                    }
                )
            )
            if session.lastError != nil {
                WindowPresenter.showMainWindow(using: openWindow)
            }
        }
    }
}
