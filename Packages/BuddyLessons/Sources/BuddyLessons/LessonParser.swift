import BuddySession
import BuddyUIModel
import Foundation

public enum LessonParser {
    public enum Error: Swift.Error, CustomStringConvertible {
        case missingFrontmatter
        case malformedYAML(underlying: Swift.Error)
        case missingRequired(field: String)
        case unknownAdvanceCondition(String)
        case unknownRole(String)
        case stepMissingExpect(stepIndex: Int)
        case noSteps
        case malformed(reason: String)

        public var description: String {
            switch self {
            case .missingFrontmatter: return "missing YAML frontmatter"
            case .malformedYAML(let e): return "malformed YAML: \(e)"
            case .missingRequired(let f): return "missing required field: \(f)"
            case .unknownAdvanceCondition(let s): return "unknown advance_when: \(s)"
            case .unknownRole(let s): return "unknown role: \(s)"
            case .stepMissingExpect(let i): return "step \(i + 1) missing expect block"
            case .noSteps: return "no steps found"
            case .malformed(let r): return "malformed: \(r)"
            }
        }
    }

    public static func parse(_ markdown: String, source: Lesson.Source = .bundled) throws -> Lesson {
        let (frontmatter, body) = try splitFrontmatter(markdown)
        let yaml: YAMLLite.YAMLValue
        do {
            yaml = try YAMLLite.parse(frontmatter)
        } catch {
            throw Error.malformedYAML(underlying: error)
        }

        guard let id = yaml.string("id"), !id.isEmpty else { throw Error.missingRequired(field: "id") }
        guard let title = yaml.string("title"), !title.isEmpty else { throw Error.missingRequired(field: "title") }
        guard let appNode = yaml.get("app") else { throw Error.missingRequired(field: "app") }
        let app: AppTarget
        if let bundle = appNode.string("bundle_id"), !bundle.isEmpty {
            app = .bundleID(bundle)
        } else if let url = appNode.string("url_match"), !url.isEmpty {
            app = .urlMatch(url)
        } else {
            throw Error.missingRequired(field: "app.bundle_id or app.url_match")
        }

        var languageHints: [String: String] = [:]
        if case .dict(let pairs)? = yaml.get("language_hints") {
            for (k, v) in pairs {
                if let s = v.asString { languageHints[k] = s }
            }
        }

        let prerequisites: [String] = (yaml.get("prerequisites")?.asList ?? [])
            .compactMap { $0.asString }
        let suggestedNext: [String] = (yaml.get("suggested_next")?.asList ?? [])
            .compactMap { $0.asString }
        let estimatedMinutes: Int? = yaml.string("estimated_minutes").flatMap(Int.init)
        let sortOrder: Int = yaml.string("sort_order").flatMap(Int.init) ?? 999

        let parts = try parseBody(body)
        guard !parts.steps.isEmpty else { throw Error.noSteps }

        return Lesson(
            id: id,
            title: title,
            languageHints: languageHints,
            app: app,
            prerequisites: prerequisites,
            estimatedMinutes: estimatedMinutes,
            intro: parts.intro,
            teachingStance: parts.teachingStance,
            steps: parts.steps,
            wrapup: parts.wrapup,
            suggestedNext: suggestedNext,
            sortOrder: sortOrder,
            source: source
        )
    }

    // MARK: - Frontmatter split

    private static func splitFrontmatter(_ md: String) throws -> (String, String) {
        let lines = md.components(separatedBy: "\n")
        var idx = 0
        // Allow blank lines before frontmatter.
        while idx < lines.count, lines[idx].trimmingCharacters(in: .whitespaces).isEmpty { idx += 1 }
        guard idx < lines.count, lines[idx].trimmingCharacters(in: .whitespaces) == "---" else {
            throw Error.missingFrontmatter
        }
        idx += 1
        let start = idx
        while idx < lines.count, lines[idx].trimmingCharacters(in: .whitespaces) != "---" {
            idx += 1
        }
        guard idx < lines.count else { throw Error.missingFrontmatter }
        let frontmatter = lines[start..<idx].joined(separator: "\n")
        let body = lines[(idx + 1)...].joined(separator: "\n")
        return (frontmatter, body)
    }

    // MARK: - Body parsing

    private struct BodyParts {
        var intro: String = ""
        var teachingStance: String?
        var steps: [LessonStep] = []
        var wrapup: String?
    }

    private static func parseBody(_ body: String) throws -> BodyParts {
        var parts = BodyParts()

        let sections = splitSections(body)

        // Intro = everything before first `## Step` (excluding the leading `#` title).
        if let intro = sections.intro {
            let scanned = extractIntro(intro)
            parts.intro = scanned.intro
            parts.teachingStance = scanned.teachingStance
        }

        for (index, sec) in sections.steps.enumerated() {
            parts.steps.append(try parseStep(sec, index: index))
        }

        if let wrap = sections.wrapup {
            parts.wrapup = extractBlockquote(wrap)
        }

        return parts
    }

    private struct SplitSections {
        var intro: String?
        var steps: [String] = []
        var wrapup: String?
    }

    private static func splitSections(_ body: String) -> SplitSections {
        let lines = body.components(separatedBy: "\n")
        var result = SplitSections()
        var current: [String] = []
        var bucket: Bucket = .intro
        enum Bucket { case intro, step, wrap }

        func flush() {
            let joined = current.joined(separator: "\n")
            switch bucket {
            case .intro:
                result.intro = joined
            case .step:
                result.steps.append(joined)
            case .wrap:
                result.wrapup = joined
            }
            current = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## Step") || trimmed.hasPrefix("##Step") {
                flush()
                bucket = .step
                current.append(line)
                continue
            }
            if trimmed.hasPrefix("## Wrap") || trimmed.hasPrefix("##Wrap") {
                flush()
                bucket = .wrap
                current.append(line)
                continue
            }
            current.append(line)
        }
        flush()
        return result
    }

    private static func extractIntro(_ section: String) -> (intro: String, teachingStance: String?) {
        var introLines: [String] = []
        var stance: String?
        let lines = section.components(separatedBy: "\n")
        var inStance = false
        var stanceLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Drop the lesson title `# …`.
            if trimmed.hasPrefix("# ") { continue }
            if trimmed.hasPrefix("**Teaching stance:**") {
                inStance = true
                let rest = trimmed.replacingOccurrences(of: "**Teaching stance:**", with: "")
                stanceLines.append(rest.trimmingCharacters(in: .whitespaces))
                continue
            }
            if inStance {
                if trimmed.isEmpty {
                    inStance = false
                    stance = stanceLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    stanceLines = []
                } else {
                    stanceLines.append(trimmed)
                }
                continue
            }
            introLines.append(line)
        }
        if !stanceLines.isEmpty {
            stance = stanceLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }
        let intro = introLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (intro, stance)
    }

    private static func parseStep(_ section: String, index: Int) throws -> LessonStep {
        let lines = section.components(separatedBy: "\n")
        var userInstruction = ""
        var teach: String?
        var teachLines: [String] = []
        var inTeach = false
        var talkingPoints: [String] = []
        var inTalking = false
        var yamlBlock: [String] = []
        var inYAML = false

        for raw in lines {
            let line = raw
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## Step") || trimmed.hasPrefix("##Step") {
                continue
            }
            if trimmed == "```yaml" {
                inYAML = true
                inTeach = false
                inTalking = false
                continue
            }
            if trimmed == "```" {
                inYAML = false
                continue
            }
            if inYAML {
                yamlBlock.append(line)
                continue
            }
            if trimmed.hasPrefix("> ") {
                let q = String(trimmed.dropFirst(2))
                if userInstruction.isEmpty {
                    userInstruction = q
                } else {
                    userInstruction += " " + q
                }
                continue
            }
            if trimmed.hasPrefix("**Teach:**") {
                inTeach = true
                let rest = trimmed.replacingOccurrences(of: "**Teach:**", with: "")
                teachLines.append(rest.trimmingCharacters(in: .whitespaces))
                continue
            }
            if trimmed.hasPrefix("**Talking points:**") {
                inTeach = false
                if !teachLines.isEmpty {
                    teach = teachLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    teachLines = []
                }
                inTalking = true
                continue
            }
            if inTalking, trimmed.hasPrefix("- ") {
                talkingPoints.append(String(trimmed.dropFirst(2)))
                continue
            }
            if inTeach {
                if trimmed.isEmpty {
                    inTeach = false
                    teach = teachLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    teachLines = []
                } else {
                    teachLines.append(trimmed)
                }
                continue
            }
            if inTalking, trimmed.isEmpty {
                inTalking = false
                continue
            }
        }
        if !teachLines.isEmpty {
            teach = teachLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }

        guard !userInstruction.isEmpty else {
            throw Error.malformed(reason: "step \(index + 1) has no `>` instruction")
        }

        var expect: StepExpectation?
        if !yamlBlock.isEmpty {
            let yamlText = yamlBlock.joined(separator: "\n")
            expect = try parseExpect(yamlText, stepIndex: index)
        }

        return LessonStep(
            id: index,
            userInstruction: userInstruction,
            teach: teach?.isEmpty == true ? nil : teach,
            talkingPoints: talkingPoints,
            expect: expect
        )
    }

    private static func parseExpect(_ yamlText: String, stepIndex: Int) throws -> StepExpectation {
        let yaml: YAMLLite.YAMLValue
        do {
            yaml = try YAMLLite.parse(yamlText)
        } catch {
            throw Error.malformedYAML(underlying: error)
        }
        guard let expect = yaml.get("expect") else {
            throw Error.stepMissingExpect(stepIndex: stepIndex)
        }
        let match: ElementMatcher? = try expect.get("match").map { try parseMatcher($0) }
        guard let advanceRaw = expect.string("advance_when") else {
            throw Error.missingRequired(field: "expect.advance_when (step \(stepIndex + 1))")
        }
        let alsoRaw = expect.string("also_advance_when")
        let advance = try makeAdvance(
            raw: advanceRaw,
            value: expect.string("advance_value"),
            matchNode: expect.get("advance_match")
        )
        let also: AdvanceCondition? = try alsoRaw.map {
            try makeAdvance(
                raw: $0,
                value: expect.string("also_advance_value"),
                matchNode: expect.get("also_advance_match")
            )
        }
        return StepExpectation(
            match: match,
            advanceWhen: advance,
            alsoAdvanceWhen: also
        )
    }

    private static func parseMatcher(_ node: YAMLLite.YAMLValue) throws -> ElementMatcher {
        let role: UIElementRole?
        if let r = node.string("role"), !r.isEmpty {
            if r == "any" {
                role = nil
            } else if let parsed = UIElementRole(rawValue: r) {
                role = parsed
            } else {
                throw Error.unknownRole(r)
            }
        } else {
            role = nil
        }
        let scope: UIElementScope?
        if let s = node.string("scope"), !s.isEmpty {
            if let parsed = UIElementScope(rawValue: s) {
                scope = parsed
            } else {
                throw Error.malformed(reason: "unknown scope: \(s)")
            }
        } else {
            scope = nil
        }
        let label = node.string("label")
        let labelContains = node.string("label_contains")
        let identifier = node.string("identifier")
        let any: [ElementMatcher]?
        if case .list(let items)? = node.get("any_of") {
            any = try items.map { try parseMatcher($0) }
        } else {
            any = nil
        }
        return ElementMatcher(
            role: role,
            scope: scope,
            label: label,
            labelContains: labelContains,
            identifier: identifier,
            anyOf: any
        )
    }

    private static func makeAdvance(
        raw: String,
        value: String?,
        matchNode: YAMLLite.YAMLValue?
    ) throws -> AdvanceCondition {
        switch raw {
        case "focused_element_changes": return .focusedElementChanges
        case "window_changes": return .windowChanges
        case "value_equals":
            return .valueEquals(value ?? "")
        case "value_starts_with":
            return .valueStartsWith(value ?? "")
        case "value_contains":
            return .valueContains(value ?? "")
        case "value_matches":
            return .valueMatches(regex: value ?? "")
        case "element_appears":
            guard let matchNode else { throw Error.missingRequired(field: "advance_match") }
            return .elementAppears(try parseMatcher(matchNode))
        case "element_disappears":
            guard let matchNode else { throw Error.missingRequired(field: "advance_match") }
            return .elementDisappears(try parseMatcher(matchNode))
        case "url_contains":
            return .urlContains(value ?? "")
        case "user_said_continue":
            return .userSaidContinue
        default:
            throw Error.unknownAdvanceCondition(raw)
        }
    }

    private static func extractBlockquote(_ section: String) -> String? {
        let lines = section.components(separatedBy: "\n")
        var pieces: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("> ") {
                pieces.append(String(trimmed.dropFirst(2)))
            } else if trimmed == ">" {
                pieces.append("")
            }
        }
        let joined = pieces.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? nil : joined
    }
}
