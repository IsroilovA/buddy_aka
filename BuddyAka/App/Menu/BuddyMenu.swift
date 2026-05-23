import BuddyVoice
import SwiftUI

struct BuddyMenu: View {
    @Environment(OnboardingState.self) private var onboarding
    @Environment(SessionCoordinator.self) private var session
    @Environment(SettingsRoute.self) private var settingsRoute
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
            NSApp.activate()
            openWindow(id: "main")
        }

        Button(String(localized: "Settings…")) {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button(String(localized: "Quit BuddyAka")) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func startSession() {
        session.start(routing: SessionStartRouting(
            onMissingPermissions: {
                onboarding.blockForPermissions()
                NSApp.activate()
                openWindow(id: "main")
            },
            onMissingAPIKey: {
                settingsRoute.selectedTab = .apiKey
                NSApp.activate()
                openSettings()
            }
        ))
        if session.lastError != nil {
            NSApp.activate()
            openWindow(id: "main")
        }
    }
}
