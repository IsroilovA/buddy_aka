import XCTest
@testable import BuddyLessons

final class BundledLessonsTests: XCTestCase {
    /// Sanity-checks that the bundled .md files in BuddyAka/Resources/Lessons
    /// parse cleanly. Uses a path relative to the package because the app bundle
    /// isn't available from `swift test`.
    func testBundledLessonsParse() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // BuddyLessonsTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // BuddyLessons
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // BuddyAka (repo root)
        let lessonsRoot = repoRoot
            .appendingPathComponent("BuddyAka")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Lessons")

        let fm = FileManager.default
        guard fm.fileExists(atPath: lessonsRoot.path) else {
            XCTFail("missing bundled lessons dir at \(lessonsRoot.path)")
            return
        }
        var found: [URL] = []
        if let enumerator = fm.enumerator(at: lessonsRoot, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.pathExtension == "md" {
                found.append(url)
            }
        }
        XCTAssertFalse(found.isEmpty, "no .md lesson files found")
        for url in found {
            let text = try String(contentsOf: url, encoding: .utf8)
            do {
                let lesson = try LessonParser.parse(text)
                XCTAssertFalse(lesson.id.isEmpty, "lesson missing id: \(url.lastPathComponent)")
                XCTAssertFalse(lesson.steps.isEmpty, "lesson \(lesson.id) has zero steps")
                for step in lesson.steps {
                    XCTAssertFalse(step.userInstruction.isEmpty, "step \(step.id) of \(lesson.id) has empty instruction")
                }
            } catch {
                XCTFail("\(url.lastPathComponent) failed: \(error)")
            }
        }
    }
}
