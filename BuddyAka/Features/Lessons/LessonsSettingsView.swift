import AppKit
import BuddyLessons
import SwiftUI
import UniformTypeIdentifiers

struct LessonsSettingsView: View {
    @Environment(LessonStore.self) private var store
    @State private var importError: String?
    @State private var showingImportPanel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let importError {
                Text(importError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if !store.loadErrors.isEmpty {
                DisclosureGroup(String(localized: "Load errors")) {
                    VStack(alignment: .leading) {
                        ForEach(store.loadErrors, id: \.self) { msg in
                            Text(msg).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            list
        }
        .padding()
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Lessons")).font(.title3).bold()
                Text(String(localized: "Drop .md files here, or use Import."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(String(localized: "Import Lesson…")) { importViaPanel() }
                .controlSize(.regular)
            Button {
                store.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(String(localized: "Reload"))
        }
    }

    private var list: some View {
        List {
            ForEach(store.lessons) { lesson in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lesson.title).font(.headline)
                        Text(lesson.id).font(.caption).foregroundStyle(.secondary)
                        Text("\(lesson.steps.count) " + String(localized: "steps"))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(lesson.source == .imported
                        ? String(localized: "Imported")
                        : String(localized: "Bundled"))
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    if lesson.source == .imported {
                        Button {
                            try? store.deleteImported(id: lesson.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(minHeight: 220)
    }

    private func importViaPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importLesson(from: url)
    }

    private func importLesson(from url: URL) {
        do {
            _ = try store.importLesson(from: url)
            importError = nil
        } catch {
            importError = String(describing: error)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: URL.self) { url, _ in
            if let url {
                DispatchQueue.main.async { importLesson(from: url) }
            }
        }
        return true
    }
}
