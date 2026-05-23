import Foundation

/// Step-cursor for Tour Mode. Pause/resume lives in `SessionCoordinator` —
/// the controller is just the walk: start, tick, stop.
public struct TourController: Sendable, Equatable {
    /// Hard cap on tour length to keep narration from dragging.
    public static let maxSteps = 12

    public enum State: Sendable, Equatable {
        case idle
        case active(currentIndex: Int, total: Int)
    }

    public enum StartResult: Sendable, Equatable {
        case started(initialStep: TourStep, total: Int)
        case alreadyActive
        case empty
    }

    public enum TickResult: Sendable, Equatable {
        case step(index: Int, total: Int, step: TourStep)
        case complete
        case idle
    }

    private var steps: [TourStep] = []
    private var index = 0

    public var state: State {
        steps.isEmpty
            ? .idle
            : .active(currentIndex: index, total: steps.count)
    }

    public init() {}

    public mutating func start(steps: [TourStep]) -> StartResult {
        if !self.steps.isEmpty { return .alreadyActive }
        guard !steps.isEmpty else { return .empty }
        self.steps = steps
        index = 0
        return .started(initialStep: steps[0], total: steps.count)
    }

    public mutating func tick() -> TickResult {
        guard !steps.isEmpty else { return .idle }
        let next = index + 1
        if next >= steps.count {
            stop()
            return .complete
        }
        index = next
        return .step(index: next, total: steps.count, step: steps[next])
    }

    public mutating func stop() {
        steps.removeAll()
        index = 0
    }
}
