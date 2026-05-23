import SwiftUI

@main
struct BuddyAkaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var permissions: PermissionsCoordinator
    @State private var onboarding  = OnboardingState()
    @State private var overlay: OverlayState
    @State private var overlayController: OverlayController
    @State private var settingsRoute: SettingsRoute
    @State private var targetTracker: TargetApplicationTracker
    @State private var session: SessionCoordinator
    @State private var buddySettings: BuddySettings
    @Environment(\.openWindow) private var openWindow

    init() {
        let state = OverlayState()
        let route = SettingsRoute()
        let perms = PermissionsCoordinator()
        let settings = BuddySettings()
        let tracker = TargetApplicationTracker()
        _overlay = State(initialValue: state)
        _overlayController = State(initialValue: OverlayController(state: state, settings: settings))
        _settingsRoute = State(initialValue: route)
        _targetTracker = State(initialValue: tracker)
        _permissions = State(initialValue: perms)
        _session = State(initialValue: SessionCoordinator(
            overlay: state,
            permissions: perms,
            targetTracker: tracker,
            buddySettings: settings
        ))
        _buddySettings = State(initialValue: settings)
    }

    var body: some Scene {
        Window("BuddyAka", id: "main") {
            MainWindow()
                .environment(permissions)
                .environment(onboarding)
                .environment(overlay)
                .environment(session)
                .environment(settingsRoute)
                .environment(buddySettings)
                .onAppear { delegate.bind(openWindow: openWindow) }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 720, height: 540)

        MenuBarExtra {
            BuddyMenu()
                .environment(permissions)
                .environment(onboarding)
                .environment(overlay)
                .environment(session)
                .environment(settingsRoute)
                .environment(buddySettings)
        } label: {
            MenuBarLabel(
                allGranted: permissions.allGranted,
                hasError: session.lastError != nil
            )
        }

        Settings {
            RootSettingsView()
                .environment(permissions)
                .environment(settingsRoute)
                .environment(buddySettings)
                .frame(minWidth: 520, minHeight: 380)
        }
    }
}

struct RootSettingsView: View {
    @Environment(SettingsRoute.self) private var route

    var body: some View {
        @Bindable var route = route
        TabView(selection: $route.selectedTab) {
            OnboardingView()
                .tabItem { Label(String(localized: "Permissions"), systemImage: "lock.shield") }
                .tag(SettingsTab.permissions)
            APIKeySettingsView()
                .tabItem { Label(String(localized: "API Key"), systemImage: "key") }
                .tag(SettingsTab.apiKey)
            BuddySettingsView()
                .tabItem { Label(String(localized: "Buddy"), systemImage: "cursorarrow") }
                .tag(SettingsTab.buddy)
        }
        .padding()
    }
}
