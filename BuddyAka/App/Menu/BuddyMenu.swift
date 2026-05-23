import BuddyVoice
import SwiftUI

struct BuddyMenu: View {
    @Environment(OnboardingState.self) private var onboarding
    @Environment(SessionCoordinator.self) private var session
    @Environment(SettingsRoute.self) private var settingsRoute
    @Environment(BuddySettings.self) private var buddySettings
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if session.isActive {
            Button(String(localized: "Stop Listening")) {
                session.stop()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        } else {
            Button(String(localized: "Start Listening")) {
                startSession()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        }

        Button(String(localized: "Open BuddyAka")) {
            WindowPresenter.showMainWindow(using: openWindow)
        }

        Button(String(localized: "Settings…")) {
            WindowPresenter.showSettings(using: openSettings)
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button(String(localized: "Quit BuddyAka")) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func startSession() {
        session.start(
            routing: SessionStartRouting(
                onMissingPermissions: {
                    onboarding.blockForPermissions()
                    WindowPresenter.showMainWindow(using: openWindow)
                },
                onMissingAPIKey: {
                    settingsRoute.selectedTab = .apiKey
                    WindowPresenter.showSettings(using: openSettings)
                }
            ),
            initialLessonID: buddySettings.selectedLessonID
        )
        if session.lastError != nil {
            WindowPresenter.showMainWindow(using: openWindow)
        }
    }
}
