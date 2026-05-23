import SwiftUI

struct WizardView: View {
    @Environment(OnboardingState.self) private var onboarding
    @Environment(PermissionsCoordinator.self) private var permissions
    @State private var hasStoredKey: Bool = (try? KeychainStore.get(key: GeminiAPIKey.keychainKey))?.isEmpty == false

    var body: some View {
        @Bindable var onboarding = onboarding
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 36)
                .padding(.top, 36)

            stepIndicator
                .padding(.vertical, 14)

            Divider()

            navBar(onboarding: onboarding)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch onboarding.currentStep {
        case .welcome:     WelcomeStep()
        case .howItWorks:  HowItWorksStep()
        case .summon:      SummonStep()
        case .permissions: WizardPermissionsStep()
        case .apiKey:      WizardAPIKeyStep(hasStoredKey: $hasStoredKey)
        case .allSet:      AllSetStep()
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(WizardStep.allCases, id: \.self) { step in
                Circle()
                    .fill(step.rawValue <= onboarding.currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func navBar(onboarding: OnboardingState) -> some View {
        HStack {
            if !onboarding.currentStep.isFirst {
                Button(String(localized: "Back")) {
                    if let prev = onboarding.currentStep.previous {
                        onboarding.currentStep = prev
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if onboarding.currentStep.isLast {
                Button(String(localized: "Finish")) {
                    onboarding.finishWizard()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button(String(localized: "Continue")) {
                    if let next = onboarding.currentStep.next {
                        onboarding.currentStep = next
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canAdvance)
            }
        }
    }

    private var canAdvance: Bool {
        switch onboarding.currentStep {
        case .permissions: return permissions.allGranted
        case .apiKey:      return hasStoredKey
        default:           return true
        }
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(verbatim: "BuddyAka")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
            Text(String(localized: "Your voice-guided onboarding buddy."))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(String(localized: "BuddyAka shows you where to click on screen and explains each step in your language."))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .padding(.top, 4)
            Spacer()
        }
    }
}

private struct HowItWorksStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeading(title: String(localized: "How it works"))
            VStack(alignment: .leading, spacing: 18) {
                bullet(symbol: "waveform",
                       title: String(localized: "You talk, BuddyAka listens."),
                       body: String(localized: "Ask in Uzbek, Russian or English."))
                bullet(symbol: "cursorarrow.rays",
                       title: String(localized: "It points, you click."),
                       body: String(localized: "BuddyAka highlights the next button. You stay in control — it never clicks for you."))
                bullet(symbol: "lock.shield",
                       title: String(localized: "Private by default."),
                       body: String(localized: "Audio and screen content only leave your Mac while a session is running."))
            }
            Spacer()
        }
    }

    private func bullet(symbol: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SummonStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeading(title: String(localized: "Summon BuddyAka"))
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    keycap("⌘"); keycap("⇧"); keycap("B")
                    Text(String(localized: "anywhere on your Mac."))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.title3)
                    Text(String(localized: "Or click the ✨ in your menu bar."))
                        .foregroundStyle(.secondary)
                }
            }
            Text(String(localized: "Press the same shortcut again to dismiss."))
                .font(.footnote)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private func keycap(_ s: String) -> some View {
        Text(s)
            .font(.system(.title2, design: .rounded).weight(.semibold))
            .frame(minWidth: 36, minHeight: 36)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.secondary.opacity(0.35))
            )
    }
}

private struct WizardPermissionsStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeading(title: String(localized: "Grant permissions"),
                        subtitle: String(localized: "Continue is enabled once all three are granted."))
            ScrollView {
                PermissionsList(filter: .all)
            }
        }
    }
}

private struct WizardAPIKeyStep: View {
    @Binding var hasStoredKey: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeading(title: String(localized: "Add your Gemini API key"),
                        subtitle: String(localized: "Stored locally in your Keychain. Never sent anywhere except Google."))
            APIKeyField(onSave: { saved in hasStoredKey = saved })
            Spacer()
        }
    }
}

private struct AllSetStep: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text(String(localized: "All set!"))
                .font(.system(size: 32, weight: .semibold, design: .rounded))
            Text(String(localized: "Look for ✨ in your menu bar. Press ⌘⇧B to start."))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
}

private struct StepHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title).bold()
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
