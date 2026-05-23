import SwiftUI

struct PermissionsBlockedView: View {
    @Environment(OnboardingState.self) private var onboarding
    @State private var showReplayConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Permissions needed to continue"))
                        .font(.title2).bold()
                    Text(String(localized: "BuddyAka is paused until these are granted. The screen returns automatically once you're set."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "Replay onboarding")) {
                    showReplayConfirm = true
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
            }

            ScrollView {
                PermissionsList(filter: .missingOnly)
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .confirmationDialog(
            String(localized: "Restart the onboarding wizard?"),
            isPresented: $showReplayConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Restart"), role: .destructive) { onboarding.replay() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
    }
}
