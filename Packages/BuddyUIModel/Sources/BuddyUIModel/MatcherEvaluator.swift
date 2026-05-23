import Foundation

public enum MatcherEvaluator {
    public static func matches(_ element: UIElementNode, _ matcher: ElementMatcher) -> Bool {
        if let any = matcher.anyOf, !any.isEmpty {
            return any.contains { matches(element, $0) }
        }

        if let scope = matcher.scope, element.scope != scope { return false }
        if let role = matcher.role, element.role != role { return false }
        if let id = matcher.identifier, !id.isEmpty {
            guard element.id == id || element.metadata["identifier"] == id else { return false }
        }
        if let label = matcher.label, !label.isEmpty {
            guard equalsIgnoringCase(element.label, label)
                || equalsIgnoringCase(element.description, label)
                || equalsIgnoringCase(element.value, label) else { return false }
        }
        if let sub = matcher.labelContains, !sub.isEmpty {
            guard containsIgnoringCase(element.label, sub)
                || containsIgnoringCase(element.description, sub)
                || containsIgnoringCase(element.value, sub) else { return false }
        }

        // An empty matcher must not match anything. Scope alone IS a legitimate
        // filter, so we let scope-only matchers through.
        if matcher.role == nil
            && matcher.scope == nil
            && (matcher.label?.isEmpty ?? true)
            && (matcher.labelContains?.isEmpty ?? true)
            && (matcher.identifier?.isEmpty ?? true) {
            return false
        }
        return true
    }

    public static func findAll(in snapshot: UISnapshot, matching matcher: ElementMatcher) -> [UIElementNode] {
        snapshot.elements.filter { matches($0, matcher) }
    }

    /// Best match: prefers the largest visible frame, then earliest DFS order.
    public static func findBest(in snapshot: UISnapshot, matching matcher: ElementMatcher) -> UIElementNode? {
        let hits = findAll(in: snapshot, matching: matcher)
        guard !hits.isEmpty else { return nil }
        return hits.enumerated().max(by: { lhs, rhs in
            let la = lhs.element.frame.w * lhs.element.frame.h
            let ra = rhs.element.frame.w * rhs.element.frame.h
            if la != ra { return la < ra }
            return lhs.offset > rhs.offset
        })?.element
    }

    private static func equalsIgnoringCase(_ a: String?, _ b: String) -> Bool {
        guard let a, !a.isEmpty else { return false }
        return a.caseInsensitiveCompare(b) == .orderedSame
    }

    private static func containsIgnoringCase(_ a: String?, _ needle: String) -> Bool {
        guard let a, !a.isEmpty, !needle.isEmpty else { return false }
        return a.range(of: needle, options: [.caseInsensitive]) != nil
    }
}
