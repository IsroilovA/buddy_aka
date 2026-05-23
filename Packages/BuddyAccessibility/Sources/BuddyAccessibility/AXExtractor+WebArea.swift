import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

extension AXExtractor {
    /// Returns the AX-coordinate screen rect of the first AXWebArea found by a
    /// bounded walk from the target's focused window. Used by browser-
    /// targeted extractors (BuddySafariDOM) to translate viewport-relative
    /// rects to screen coordinates without depending on AX internals.
    ///
    /// Caps total visited nodes — Safari pages can bury the web area behind
    /// hundreds of AX wrappers and page nodes, so this mirrors the full
    /// extractor's traversal without paying for label/frame normalization.
    /// Returns nil if no AXWebArea is reachable (e.g. Top Sites / start page,
    /// or a target that isn't a browser at all).
    public func webAreaFrame(target: AXTarget) async throws -> CGRect? {
        guard AXIsProcessTrusted() else { throw Error.accessibilityNotTrusted }

        let app: NSRunningApplication
        switch target {
        case .frontmost:
            guard let a = NSWorkspace.shared.frontmostApplication else {
                throw Error.appNotFound(target)
            }
            app = a
        case .pid(let pid):
            guard let a = NSRunningApplication(processIdentifier: pid) else {
                throw Error.appNotFound(target)
            }
            app = a
        case .bundleID(let id):
            guard let a = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else {
                throw Error.appNotFound(target)
            }
            app = a
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXAttr.setTimeout(appElement, seconds: 0.5)
        guard let win = AXAttr.copy(appElement, kAXFocusedWindowAttribute as String) else {
            return nil
        }
        let winEl = win as! AXUIElement

        let deadline = Date().addingTimeInterval(0.75)
        let maxVisited = 2_000
        let maxDepth = 25

        var stack: [(AXUIElement, Int)] = [(winEl, 0)]
        var visited = 0
        while let (el, depth) = stack.popLast() {
            if visited >= maxVisited || Date() >= deadline { break }
            visited += 1

            if let role = AXAttr.string(el, kAXRoleAttribute as String), role == "AXWebArea" {
                return AXAttr.frame(el)
            }

            if depth + 1 <= maxDepth {
                for child in AXAttr.children(el).reversed() {
                    stack.append((child, depth + 1))
                }
            }
        }
        return nil
    }
}
