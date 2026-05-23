import BuddyLessons
import BuddySession
import BuddyVoice
import SwiftUI

struct HomeView: View {
    @Environment(OnboardingState.self) private var onboarding
    @Environment(PermissionsCoordinator.self) private var permissions
    @Environment(SessionCoordinator.self) private var session
    @Environment(SettingsRoute.self) private var settingsRoute
    @Environment(BuddySettings.self) private var buddySettings
    @Environment(LessonStore.self) private var lessonStore
    @Environment(\.openSettings) private var openSettings
    @State private var showReplayConfirm = false

    private let gridColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                Text(verbatim: "BuddyAka")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))

                Text(String(localized: "Learn software hands-on with a voice tutor."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            statusPill

            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    freeFormCard
                    ForEach(lessonStore.lessons) { lesson in
                        lessonCard(for: lesson)
                    }
                }
                .padding(.horizontal, 4)
            }

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
                            : startButtonLabel,
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

            Spacer(minLength: 4)

            Text(String(localized: "BuddyAka is running. Click ✨ in the menu bar anytime."))
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .confirmationDialog(
            String(localized: "Restart the onboarding wizard?"),
            isPresented: $showReplayConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Restart"), role: .destructive) { onboarding.replay() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
    }

    // MARK: - Status

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

    // MARK: - Lesson grid

    private var freeFormCard: some View {
        let selected = buddySettings.selectedLessonID == nil
        return cardFrame(selected: selected) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(String(localized: "Free-form"))
                    .font(.headline)
                Text(String(localized: "Buddy helps with anything on screen."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .onTapGesture { buddySettings.selectedLessonID = nil }
    }

    private func lessonCard(for lesson: Lesson) -> some View {
        let selected = buddySettings.selectedLessonID == lesson.id
        return cardFrame(selected: selected) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon(for: lesson))
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(displayTitle(for: lesson))
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle(for: lesson))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !lesson.intro.isEmpty {
                    Text(firstSentence(lesson.intro))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .onTapGesture {
            buddySettings.selectedLessonID = (buddySettings.selectedLessonID == lesson.id) ? nil : lesson.id
        }
    }

    private func cardFrame<Content: View>(selected: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 2 : 1)
            )
    }

    // MARK: - Start button

    private var startButtonLabel: String {
        if let id = buddySettings.selectedLessonID,
           let lesson = lessonStore.lesson(id: id) {
            return String(localized: "Start: \(displayTitle(for: lesson))")
        }
        return String(localized: "Start (⌘⇧B)")
    }

    private func startSession() {
        session.start(
            routing: SessionStartRouting(
                onMissingPermissions: { onboarding.blockForPermissions() },
                onMissingAPIKey: {
                    settingsRoute.selectedTab = .apiKey
                    WindowPresenter.showSettings(using: openSettings)
                }
            ),
            initialLessonID: buddySettings.selectedLessonID
        )
    }

    // MARK: - Display helpers

    private func icon(for lesson: Lesson) -> String {
        switch lesson.app {
        case .bundleID(let id) where id.contains("systempreferences"): return "gearshape"
        case .bundleID(let id) where id.contains("finder"): return "folder"
        case .bundleID: return "app"
        case .urlMatch(let s) where s.contains("spreadsheets"): return "tablecells"
        case .urlMatch(let s) where s.contains("photopea"): return "photo"
        case .urlMatch(let s) where s.contains("figma"): return "pencil.and.ruler"
        case .urlMatch(let s) where s.contains("atlassian"): return "list.clipboard"
        case .urlMatch(let s) where s.contains("canva"): return "paintbrush"
        case .urlMatch(let s) where s.contains("presentation"): return "rectangle.on.rectangle"
        case .urlMatch(let s) where s.contains("document"): return "doc.text"
        case .urlMatch(let s) where s.contains("slack"): return "bubble.left"
        case .urlMatch(let s) where s.contains("drive"): return "externaldrive"
        case .urlMatch(let s) where s.contains("youtube"): return "play.rectangle"
        case .urlMatch(let s) where s.contains("chatgpt"): return "brain"
        case .urlMatch(let s) where s.contains("claude"): return "brain.head.profile"
        case .urlMatch: return "globe"
        }
    }

    private func displayTitle(for lesson: Lesson) -> String {
        let language = Locale.current.language.languageCode?.identifier
        if let language, let hint = lesson.languageHints[language], !hint.isEmpty {
            return hint
        }
        return lesson.title
    }

    private func subtitle(for lesson: Lesson) -> String {
        var parts: [String] = []
        if let mins = lesson.estimatedMinutes {
            parts.append("\(mins) " + String(localized: "min"))
        }
        parts.append("\(lesson.steps.count) " + String(localized: "steps"))
        return parts.joined(separator: " · ")
    }

    private func firstSentence(_ text: String) -> String {
        if let end = text.firstIndex(where: { $0 == "." || $0 == "\n" }) {
            return String(text[..<end])
        }
        return text
    }
}
