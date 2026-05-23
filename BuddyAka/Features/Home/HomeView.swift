import BuddyVoice
import SwiftUI

struct HomeView: View {
    @Environment(OnboardingState.self) private var onboarding
    @Environment(PermissionsCoordinator.self) private var permissions
    @Environment(SessionCoordinator.self) private var session
    @Environment(SettingsRoute.self) private var settingsRoute
    @Environment(\.openSettings) private var openSettings
    @State private var showReplayConfirm = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)

            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                Text(verbatim: "BuddyAka")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))

                Text(String(localized: "Your voice-guided onboarding buddy."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            statusPill

            HStack(spacing: 12) {
                Button {
                    if session.isActive {
                        session.stop()
                    } else {
                        startSession()
                    }
                } label: {
                    Label(
                        session.isActive
                            ? String(localized: "Stop (⌘⇧B)")
                            : String(localized: "Try it (⌘⇧B)"),
                        systemImage: session.isActive ? "stop.fill" : "mic.fill"
                    )
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(String(localized: "Replay onboarding")) {
                    showReplayConfirm = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Spacer()

            Text(String(localized: "BuddyAka is running. Click ✨ in the menu bar anytime."))
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .confirmationDialog(
            String(localized: "Restart the onboarding wizard?"),
            isPresented: $showReplayConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Restart"), role: .destructive) { onboarding.replay() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if permissions.allGranted {
            pill(text: String(localized: "Ready"), symbol: "checkmark.circle.fill", tint: .green)
        } else {
            pill(text: String(localized: "Setup incomplete"), symbol: "exclamationmark.triangle.fill", tint: .orange)
        }
    }

    private func pill(text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(text).fontWeight(.medium)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(tint)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.35)))
    }

    private func startSession() {
        session.start(routing: SessionStartRouting(
            onMissingPermissions: { onboarding.blockForPermissions() },
            onMissingAPIKey: {
                settingsRoute.selectedTab = .apiKey
                NSApp.activate()
                openSettings()
            }
        ))
    }
}
