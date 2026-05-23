import BuddySession
import BuddyUIModel
import Foundation

public struct Lesson: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let languageHints: [String: String]
    /// Advisory metadata: which app the lesson is designed for. Used by the
    /// lesson picker UI for grouping / icons. NOT a runtime gate — the walker
    /// runs steps regardless, and each step's matcher decides when it advances.
    public let app: AppTarget
    public let prerequisites: [String]
    public let estimatedMinutes: Int?
    public let intro: String
    public let teachingStance: String?
    public let steps: [LessonStep]
    public let wrapup: String?
    public let suggestedNext: [String]
    public let sortOrder: Int
    public let source: Source

    public var isOpenLoop: Bool { steps.isEmpty }

    public enum Source: Sendable, Equatable {
        case bundled
        case imported
    }

    public init(
        id: String,
        title: String,
        languageHints: [String: String] = [:],
        app: AppTarget,
        prerequisites: [String] = [],
        estimatedMinutes: Int? = nil,
        intro: String = "",
        teachingStance: String? = nil,
        steps: [LessonStep] = [],
        wrapup: String? = nil,
        suggestedNext: [String] = [],
        sortOrder: Int = 999,
        source: Source = .bundled
    ) {
        self.id = id
        self.title = title
        self.languageHints = languageHints
        self.app = app
        self.prerequisites = prerequisites
        self.estimatedMinutes = estimatedMinutes
        self.intro = intro
        self.teachingStance = teachingStance
        self.steps = steps
        self.wrapup = wrapup
        self.suggestedNext = suggestedNext
        self.sortOrder = sortOrder
        self.source = source
    }
}

public struct LessonStep: Sendable, Equatable, Identifiable {
    public let id: Int
    public let userInstruction: String
    public let teach: String?
    public let talkingPoints: [String]
    public let expect: StepExpectation?

    public init(
        id: Int,
        userInstruction: String,
        teach: String? = nil,
        talkingPoints: [String] = [],
        expect: StepExpectation? = nil
    ) {
        self.id = id
        self.userInstruction = userInstruction
        self.teach = teach
        self.talkingPoints = talkingPoints
        self.expect = expect
    }
}

public struct StepExpectation: Sendable, Equatable {
    public let match: ElementMatcher?
    public let advanceWhen: AdvanceCondition
    public let alsoAdvanceWhen: AdvanceCondition?

    public init(
        match: ElementMatcher? = nil,
        advanceWhen: AdvanceCondition,
        alsoAdvanceWhen: AdvanceCondition? = nil
    ) {
        self.match = match
        self.advanceWhen = advanceWhen
        self.alsoAdvanceWhen = alsoAdvanceWhen
    }
}
