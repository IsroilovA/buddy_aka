import Foundation

public enum AXTarget: Sendable, Equatable {
    case frontmost
    case pid(pid_t)
    case bundleID(String)
}
