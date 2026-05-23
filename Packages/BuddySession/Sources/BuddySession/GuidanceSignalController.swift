import BuddyAccessibility
import CoreGraphics
import Foundation

public enum GuidanceSignalOutput: Equatable {
    case none
    case scheduleSettle
    case send(BuddySignal)
}

public struct GuidanceSignalController {
    private enum Mode: Equatable {
        case idle
        case guiding(targetID: String, frame: CGRect)
        case settling(action: UserAction, sawMeaningfulAX: Bool)
    }

    private enum UserAction: Equatable {
        case targetClick
        case offTargetClick
        case axProgress
    }

    private var mode: Mode = .idle
    private let hitSlack: CGFloat

    public init(hitSlack: CGFloat = 40) {
        self.hitSlack = hitSlack
    }

    public mutating func reset() {
        mode = .idle
    }

    public mutating func startGuiding(elementID: String, frame: CGRect) {
        mode = .guiding(targetID: elementID, frame: frame)
    }

    public mutating func handleMouseClick(_ point: CGPoint) -> GuidanceSignalOutput {
        guard case .guiding(_, let frame) = mode else { return .none }
        let action: UserAction = frame.insetBy(dx: -hitSlack, dy: -hitSlack).contains(point)
            ? .targetClick
            : .offTargetClick
        mode = .settling(action: action, sawMeaningfulAX: false)
        return .scheduleSettle
    }

    public mutating func handleAXEvent(_ event: AXEvent) -> GuidanceSignalOutput {
        guard isMeaningfulProgressEvent(event) else { return .none }

        switch mode {
        case .guiding:
            mode = .settling(action: .axProgress, sawMeaningfulAX: true)
            return .scheduleSettle
        case .settling(let action, _):
            mode = .settling(action: action, sawMeaningfulAX: true)
            return .none
        case .idle:
            return .none
        }
    }

    public mutating func handleTimeout() -> GuidanceSignalOutput {
        guard case .guiding = mode else { return .none }
        return .send(.idleTimeout)
    }

    public mutating func finishSettling() -> GuidanceSignalOutput {
        guard case .settling(let action, let sawMeaningfulAX) = mode else { return .none }
        mode = .idle
        switch action {
        case .targetClick:
            return .send(sawMeaningfulAX ? .screenChanged : .targetClicked)
        case .offTargetClick:
            return .send(.userClickedElsewhere)
        case .axProgress:
            return .send(.screenChanged)
        }
    }

    private func isMeaningfulProgressEvent(_ event: AXEvent) -> Bool {
        switch event {
        case .focusedElementChanged, .focusedWindowChanged, .windowCreated:
            return true
        case .layoutChanged, .valueChanged, .elementDestroyed, .menuOpened, .menuClosed:
            return false
        }
    }
}
