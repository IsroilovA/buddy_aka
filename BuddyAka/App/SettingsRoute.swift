import Observation

enum SettingsTab: Hashable {
    case permissions
    case apiKey
    case buddy
    case lessons
}

@MainActor
@Observable
final class SettingsRoute {
    var selectedTab: SettingsTab = .permissions
}
