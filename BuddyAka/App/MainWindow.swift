import SwiftUI

struct MainWindow: View {
    @Environment(OnboardingState.self) private var onboarding
    @Environment(PermissionsCoordinator.self) private var permissions
    @Environment(SessionCoordinator.self) private var session

    var body: some View {
        Group {
            switch onboarding.route {
            case .wizard:  WizardView()
            case .home:    HomeView()
            case .blocked: PermissionsBlockedView()
            }
        }
        .frame(minWidth: 560, idealWidth: 720, minHeight: 420, idealHeight: 540)
        .onChange(of: permissions.allGranted) { _, granted in
            if granted && onboarding.route == .blocked {
                onboarding.returnToHome()
            }
        }
        .alert(
            session.lastError?.localizedTitle ?? String(localized: "Couldn't start session"),
            isPresented: Binding(
                get: { session.lastError != nil },
                set: { if !$0 { session.clearLastError() } }
            )
        ) {
            Button(String(localized: "OK")) {}
        } message: {
            Text(session.lastError?.localizedMessage ?? "")
        }
    }
}
