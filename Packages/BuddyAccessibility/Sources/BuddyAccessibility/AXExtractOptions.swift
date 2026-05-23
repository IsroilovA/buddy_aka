import Foundation

public struct AXExtractOptions: Sendable {
    public var windowOnly: Bool
    public var onScreenOnly: Bool
    public var maxElements: Int
    public var maxDepth: Int
    public var perElementTimeoutMs: Int
    public var overallTimeoutMs: Int

    public init(
        windowOnly: Bool = true,
        onScreenOnly: Bool = true,
        maxElements: Int = 500,
        maxDepth: Int = 25,
        perElementTimeoutMs: Int = 200,
        overallTimeoutMs: Int = 1000
    ) {
        self.windowOnly = windowOnly
        self.onScreenOnly = onScreenOnly
        self.maxElements = maxElements
        self.maxDepth = maxDepth
        self.perElementTimeoutMs = perElementTimeoutMs
        self.overallTimeoutMs = overallTimeoutMs
    }
}
