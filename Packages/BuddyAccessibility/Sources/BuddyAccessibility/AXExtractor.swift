import AppKit
import ApplicationServices
import BuddyUIModel
import CoreGraphics
import Foundation

public actor AXExtractor {
    public init() {}

    public enum Error: Swift.Error, Sendable {
        case accessibilityNotTrusted
        case appNotFound(AXTarget)
        case noFocusedWindow
        case axError(AXError, attribute: String?)
    }

    public func extract(
        target: AXTarget,
        options: AXExtractOptions = .init()
    ) async throws -> (snapshot: UISnapshot, resolver: AXSnapshotResolver) {
        guard AXIsProcessTrusted() else { throw Error.accessibilityNotTrusted }

        let started = Date()
        let app = try resolveApp(target: target)
        let bundleID = app.bundleIdentifier
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXAttr.setTimeout(appElement, seconds: Float(options.perElementTimeoutMs) / 1000.0)

        let root: AXUIElement
        var windowTitle: String?
        if options.windowOnly {
            guard let win = AXAttr.copy(appElement, kAXFocusedWindowAttribute as String) else {
                throw Error.noFocusedWindow
            }
            let winElement = win as! AXUIElement
            root = winElement
            windowTitle = AXAttr.string(winElement, kAXTitleAttribute as String)
        } else {
            root = appElement
        }

        let screenUnion: CGRect? = options.onScreenOnly ? await Self.screensUnion() : nil
        let deadline = started.addingTimeInterval(TimeInterval(options.overallTimeoutMs) / 1000.0)

        var idGen = AXIDGenerator()
        var elements: [UIElementNode] = []
        var resolverMap: [String: AXUIElement] = [:]
        var frameMap: [String: CGRect] = [:]
        var nodeMap: [String: UIElementNode] = [:]
        var scanned = 0
        var truncated = false
        var url: String?

        // Iterative DFS with caps. Stack holds (element, depth).
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        while let (el, depth) = stack.popLast() {
            if Task.isCancelled { truncated = true; break }
            if Date() >= deadline { truncated = true; break }
            if elements.count >= options.maxElements { truncated = true; break }

            scanned += 1

            let attrs = AXAttr.batch(el)
            let role = attrs.role ?? ""
            let subrole = attrs.subrole
            let text = Self.labelAndDescription(from: attrs)
            let identifier = attrs.identifier
            let enabled = attrs.enabled ?? true
            let focused = attrs.focused ?? false
            let frame = attrs.frame

            // First AXWebArea we see — grab its URL for browser flows.
            if url == nil, role == "AXWebArea" {
                if let raw = AXAttr.copy(el, "AXURL") {
                    if let nsurl = raw as? URL {
                        url = nsurl.absoluteString
                    } else if let s = raw as? String {
                        url = s
                    }
                }
            }

            let candidate = AXFilter.Candidate(
                role: role,
                label: text.label,
                identifier: identifier,
                frame: frame,
                enabled: enabled
            )
            if AXFilter.keep(candidate, onScreenOnly: options.onScreenOnly, screenUnion: screenUnion),
               let frame {
                let id = idGen.next()
                let rawValue = AXAttr.displayValue(el)
                let value = Self.safeValue(for: attrs, raw: rawValue, label: text.label, description: text.description)
                let normalized = UINormalization.axRole(role, subrole: subrole)
                var metadata = normalized.1
                if let identifier { metadata["identifier"] = identifier }
                let node = UIElementNode(
                    id: id,
                    source: .ax,
                    role: normalized.0,
                    label: text.label,
                    description: text.description,
                    value: value,
                    hasValue: rawValue != nil,
                    enabled: enabled,
                    focused: focused,
                    frame: UIFrame(frame),
                    metadata: metadata
                )
                elements.append(node)
                resolverMap[id] = el
                frameMap[id] = frame
                nodeMap[id] = node
            }

            if depth + 1 <= options.maxDepth {
                let kids = AXAttr.children(el)
                // Push in reverse so popLast() processes them in document order.
                for child in kids.reversed() {
                    stack.append((child, depth + 1))
                }
            }
        }

        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        let snapshot = UISnapshot(
            app: bundleID,
            windowTitle: windowTitle,
            url: url,
            elements: elements,
            stats: UISnapshotStats(
                scanned: scanned,
                kept: elements.count,
                truncated: truncated,
                elapsedMs: elapsedMs
            )
        )
        let resolver = AXSnapshotResolver(elements: resolverMap, frames: frameMap, nodes: nodeMap)
        return (snapshot, resolver)
    }

    // MARK: - Helpers

    private func resolveApp(target: AXTarget) throws -> NSRunningApplication {
        switch target {
        case .frontmost:
            guard let app = NSWorkspace.shared.frontmostApplication else {
                throw Error.appNotFound(target)
            }
            return app
        case .pid(let pid):
            guard let app = NSRunningApplication(processIdentifier: pid) else {
                throw Error.appNotFound(target)
            }
            return app
        case .bundleID(let id):
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else {
                throw Error.appNotFound(target)
            }
            return app
        }
    }

    // AXDescription beats AXTitle for unlabeled icon buttons; AXTitle beats it
    // for normal text-labeled controls. Try title first, then description.
    internal static func bestLabel(from attrs: AXAttrBatch) -> String? {
        labelAndDescription(from: attrs).label
    }

    internal static func labelAndDescription(from attrs: AXAttrBatch) -> (label: String?, description: String?) {
        let candidates = [attrs.title, attrs.description, attrs.help]
            .compactMap { UINormalization.cleanText($0) }
        let label = candidates.first
        let description = candidates.dropFirst().first { $0 != label }
        return (label, description)
    }

    private static func safeValue(
        for attrs: AXAttrBatch,
        raw: String?,
        label: String?,
        description: String?
    ) -> String? {
        let normalizedRole = UINormalization.axRole(attrs.role, subrole: attrs.subrole).0
        guard raw != nil else { return nil }
        if UINormalization.isSensitiveField(
            role: normalizedRole,
            label: label,
            description: description,
            placeholder: nil,
            inputType: nil,
            name: nil,
            id: attrs.identifier
        ) {
            return nil
        }
        switch normalizedRole {
        case .checkbox, .radio, .switchControl, .slider, .spinbutton, .combobox:
            return UINormalization.cleanText(raw, maxLength: 120)
        default:
            return nil
        }
    }

    internal static func hasSafeValue(_ attrs: AXAttrBatch, label: String?, description: String?) -> Bool {
        guard let role = attrs.role else { return false }
        let normalizedRole = UINormalization.axRole(role, subrole: attrs.subrole).0
        return !UINormalization.isSensitiveField(
            role: normalizedRole,
            label: label,
            description: description,
            placeholder: nil,
            inputType: nil,
            name: nil,
            id: attrs.identifier
        )
    }

    internal static func normalizedRole(from attrs: AXAttrBatch) -> UIElementRole {
        UINormalization.axRole(attrs.role, subrole: attrs.subrole).0
    }

    internal static func bestDescription(from attrs: AXAttrBatch) -> String? {
        labelAndDescription(from: attrs).description
    }

    internal static func normalizedMetadata(from attrs: AXAttrBatch) -> [String: String] {
        var metadata = UINormalization.axRole(attrs.role, subrole: attrs.subrole).1
        if let identifier = attrs.identifier { metadata["identifier"] = identifier }
        return metadata
    }

    internal static func safeDisplayValueForTests(_ attrs: AXAttrBatch, raw: String?, label: String?, description: String?) -> String? {
        guard let raw else { return nil }
        let role = UINormalization.axRole(attrs.role, subrole: attrs.subrole).0
        if UINormalization.isSensitiveField(role: role, label: label, description: description, placeholder: nil, inputType: nil, name: nil, id: attrs.identifier) {
            return nil
        }
        switch role {
        case .checkbox, .radio, .switchControl, .slider, .spinbutton, .combobox:
            return UINormalization.cleanText(raw, maxLength: 120)
        default:
            return nil
        }
    }

    internal static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let clean = UINormalization.cleanText(value) { return clean }
        }
        return nil
    }

    @MainActor
    private static func screensUnion() -> CGRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return .infinite }
        return screens.reduce(.null) { $0.union($1.frame) }
    }
}
