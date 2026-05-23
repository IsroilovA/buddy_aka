import Foundation
import Observation

enum OnboardingRoute {
    case wizard
    case home
    case blocked
}

enum WizardStep: Int, CaseIterable {
    case welcome = 0
    case howItWorks
    case summon
    case permissions
    case apiKey
    case allSet

    var next: WizardStep? { WizardStep(rawValue: rawValue + 1) }
    var previous: WizardStep? { WizardStep(rawValue: rawValue - 1) }
    var isLast: Bool { next == nil }
    var isFirst: Bool { previous == nil }
}

@MainActor
@Observable
final class OnboardingState {
    var route: OnboardingRoute
    var currentStep: WizardStep = .welcome

    private static let completedKey = "hasCompletedOnboarding"

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.completedKey) }
    }

    init() {
        let completed = UserDefaults.standard.bool(forKey: Self.completedKey)
        self.hasCompletedOnboarding = completed
        self.route = completed ? .home : .wizard
    }

    func finishWizard() {
        hasCompletedOnboarding = true
        route = .home
    }

    func replay() {
        currentStep = .welcome
        route = .wizard
    }

    func blockForPermissions() {
        route = .blocked
    }

    func returnToHome() {
        route = .home
    }
}
