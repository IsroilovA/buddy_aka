import BuddyLessons
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
    @State private var lessonStore: LessonStore
    @State private var demoAnimator: DemoCursorAnimator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    init() {
        let state = OverlayState()
        let route = SettingsRoute()
        let perms = PermissionsCoordinator()
        let settings = BuddySettings()
        let tracker = TargetApplicationTracker()
        let store = LessonStore(userDirectory: LessonStore.defaultUserDirectory)
        _overlay = State(initialValue: state)
        _overlayController = State(initialValue: OverlayController(state: state, settings: settings))
        _settingsRoute = State(initialValue: route)
        _targetTracker = State(initialValue: tracker)
        _permissions = State(initialValue: perms)
        _session = State(initialValue: SessionCoordinator(
            overlay: state,
            permissions: perms,
            targetTracker: tracker,
            buddySettings: settings,
            lessonStore: store
        ))
        _buddySettings = State(initialValue: settings)
        _lessonStore = State(initialValue: store)
        _demoAnimator = State(initialValue: DemoCursorAnimator(overlay: state))
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
                .environment(lessonStore)
                .onAppear { bindDelegateIfNeeded() }
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
                .environment(lessonStore)
                .environment(demoAnimator)
        } label: {
            MenuBarLabel(
                allGranted: permissions.allGranted,
                hasError: session.lastError != nil
            )
            .onAppear { bindDelegateIfNeeded() }
        }

        Settings {
            RootSettingsView()
                .environment(permissions)
                .environment(settingsRoute)
                .environment(buddySettings)
                .environment(lessonStore)
                .frame(minWidth: 520, minHeight: 380)
        }
    }
}

extension BuddyAkaApp {
    private func bindDelegateIfNeeded() {
        delegate.bind(
            openWindow: openWindow,
            openSettings: openSettings,
            session: session,
            onboarding: onboarding,
            settingsRoute: settingsRoute
        )
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
            LessonsSettingsView()
                .tabItem { Label(String(localized: "Lessons"), systemImage: "book") }
                .tag(SettingsTab.lessons)
        }
        .padding()
    }
}
