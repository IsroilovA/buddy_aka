import Foundation
import Observation
import os

@MainActor
@Observable
public final class LessonStore {
    public private(set) var lessons: [Lesson] = []
    public private(set) var loadErrors: [String] = []

    private let bundle: Bundle
    private let userDirectory: URL
    private let log = Logger(subsystem: "dev.alisher.BuddyAka", category: "LessonStore")

    public init(bundle: Bundle = .main, userDirectory: URL) {
        self.bundle = bundle
        self.userDirectory = userDirectory
        ensureUserDirectory()
        reload()
    }

    public func reload() {
        var collected: [String: Lesson] = [:]
        var errors: [String] = []

        for url in bundledLessonURLs() {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let lesson = try LessonParser.parse(text, source: .bundled)
                collected[lesson.id] = lesson
            } catch {
                let msg = "\(url.lastPathComponent): \(error)"
                errors.append(msg)
                log.error("bundled lesson parse failed — \(msg, privacy: .public)")
            }
        }
        for url in userLessonURLs() {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let lesson = try LessonParser.parse(text, source: .imported)
                collected[lesson.id] = lesson
            } catch {
                let msg = "\(url.lastPathComponent): \(error)"
                errors.append(msg)
                log.error("user lesson parse failed — \(msg, privacy: .public)")
            }
        }

        self.lessons = collected.values.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        self.loadErrors = errors
    }

    public func lesson(id: String) -> Lesson? {
        lessons.first { $0.id == id }
    }

    public func importLesson(from url: URL) throws -> Lesson {
        let text = try String(contentsOf: url, encoding: .utf8)
        let parsed = try LessonParser.parse(text, source: .imported)
        ensureUserDirectory()
        let destination = userDirectory.appendingPathComponent("\(parsed.id).md")
        try? FileManager.default.removeItem(at: destination)
        try text.write(to: destination, atomically: true, encoding: .utf8)
        reload()
        return parsed
    }

    public func deleteImported(id: String) throws {
        let url = userDirectory.appendingPathComponent("\(id).md")
        try FileManager.default.removeItem(at: url)
        reload()
    }

    public func userDirectoryURL() -> URL { userDirectory }

    // MARK: - Private

    private func ensureUserDirectory() {
        try? FileManager.default.createDirectory(
            at: userDirectory,
            withIntermediateDirectories: true
        )
    }

    private func bundledLessonURLs() -> [URL] {
        var urls: [URL] = []
        // PBXFileSystemSynchronizedRootGroup flattens resource files into Contents/Resources/,
        // so `Lessons/sheets/foo.md` ends up as `Resources/foo.md`. Find by extension first.
        if let flat = bundle.urls(forResourcesWithExtension: "md", subdirectory: nil) {
            urls.append(contentsOf: flat)
        }
        // Fallback: walk a real `Lessons/` subdir if it exists (future Xcode setting flip).
        if let resourceURL = bundle.resourceURL {
            let lessonsRoot = resourceURL.appendingPathComponent("Lessons", isDirectory: true)
            urls.append(contentsOf: walkMarkdown(at: lessonsRoot))
        }
        return urls
    }

    private func userLessonURLs() -> [URL] {
        walkMarkdown(at: userDirectory)
    }

    private func walkMarkdown(at root: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var results: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "md" {
                results.append(url)
            }
        }
        return results
    }
}

public extension LessonStore {
    static var defaultUserDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("dev.alisher.BuddyAka", isDirectory: true)
            .appendingPathComponent("Lessons", isDirectory: true)
    }
}
