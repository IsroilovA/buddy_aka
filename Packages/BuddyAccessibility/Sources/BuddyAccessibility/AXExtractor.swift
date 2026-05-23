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

        let fragment = walk(
            root: root,
            scope: .appWindow,
            idPrefix: "aw",
            options: options,
            screenUnion: screenUnion,
            started: started,
            captureURL: true
        )

        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        let snapshot = UISnapshot(
            app: bundleID,
            windowTitle: windowTitle,
            url: fragment.url,
            elements: fragment.elements,
            stats: UISnapshotStats(
                scanned: fragment.scanned,
                kept: fragment.elements.count,
                truncated: fragment.truncated,
                elapsedMs: elapsedMs
            )
        )
        let resolver = AXSnapshotResolver(
            elements: fragment.resolverMap,
            frames: fragment.frameMap,
            nodes: fragment.nodeMap
        )
        return (snapshot, resolver)
    }

    /// Extract the system menu bar of the given pid (frontmost app's pid). Returns
    /// the top-level menu bar items (Apple menu, app menus, extras menu) WITHOUT
    /// drilling into open submenu contents — that tree is unbounded and only
    /// becomes addressable once the user opens a menu (at which point the regular
    /// AX events reveal the content).
    public func extractMenuBar(
        forPID pid: pid_t,
        options: AXExtractOptions = AXExtractOptions(windowOnly: false, maxElements: 64, maxDepth: 3, overallTimeoutMs: 400)
    ) async throws -> (elements: [UIElementNode], resolver: AXSnapshotResolver) {
        guard AXIsProcessTrusted() else { throw Error.accessibilityNotTrusted }
        let appElement = AXUIElementCreateApplication(pid)
        AXAttr.setTimeout(appElement, seconds: Float(options.perElementTimeoutMs) / 1000.0)

        var allElements: [UIElementNode] = []
        var resolverMap: [String: AXUIElement] = [:]
        var frameMap: [String: CGRect] = [:]
        var nodeMap: [String: UIElementNode] = [:]
        var truncatedAny = false
        var scannedTotal = 0
        let started = Date()
        let screenUnion: CGRect? = options.onScreenOnly ? await Self.screensUnion() : nil

        for attr in [kAXMenuBarAttribute as String, "AXExtrasMenuBar"] {
            guard let raw = AXAttr.copy(appElement, attr) else { continue }
            let bar = unsafeDowncast(raw, to: AXUIElement.self)
            let fragment = walk(
                root: bar,
                scope: .menuBar,
                idPrefix: "mb",
                options: options,
                screenUnion: screenUnion,
                started: started,
                captureURL: false
            )
            allElements.append(contentsOf: fragment.elements)
            resolverMap.merge(fragment.resolverMap) { _, b in b }
            frameMap.merge(fragment.frameMap) { _, b in b }
            nodeMap.merge(fragment.nodeMap) { _, b in b }
            scannedTotal += fragment.scanned
            truncatedAny = truncatedAny || fragment.truncated
        }

        return (allElements, AXSnapshotResolver(elements: resolverMap, frames: frameMap, nodes: nodeMap))
    }

    /// Extract the Dock as its own AX tree. Best-effort — the Dock is its own
    /// process (`com.apple.dock`). If it can't be reached, returns empty arrays.
    public func extractDock(
        options: AXExtractOptions = AXExtractOptions(windowOnly: false, maxElements: 80, maxDepth: 5, overallTimeoutMs: 400)
    ) async throws -> (elements: [UIElementNode], resolver: AXSnapshotResolver) {
        guard AXIsProcessTrusted() else { throw Error.accessibilityNotTrusted }
        guard let dockApp = await MainActor.run(body: {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        }) else {
            return ([], AXSnapshotResolver(elements: [:], frames: [:], nodes: [:]))
        }
        let appElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        AXAttr.setTimeout(appElement, seconds: Float(options.perElementTimeoutMs) / 1000.0)
        let screenUnion: CGRect? = options.onScreenOnly ? await Self.screensUnion() : nil
        let fragment = walk(
            root: appElement,
            scope: .dock,
            idPrefix: "dk",
            options: options,
            screenUnion: screenUnion,
            started: Date(),
            captureURL: false
        )
        let resolver = AXSnapshotResolver(
            elements: fragment.resolverMap,
            frames: fragment.frameMap,
            nodes: fragment.nodeMap
        )
        return (fragment.elements, resolver)
    }

    // MARK: - Walk (shared DFS)

    private struct WalkFragment {
        var elements: [UIElementNode] = []
        var resolverMap: [String: AXUIElement] = [:]
        var frameMap: [String: CGRect] = [:]
        var nodeMap: [String: UIElementNode] = [:]
        var scanned: Int = 0
        var truncated: Bool = false
        var url: String?
    }

    private func walk(
        root: AXUIElement,
        scope: UIElementScope,
        idPrefix: String,
        options: AXExtractOptions,
        screenUnion: CGRect?,
        started: Date,
        captureURL: Bool
    ) -> WalkFragment {
        var fragment = WalkFragment()
        let deadline = started.addingTimeInterval(TimeInterval(options.overallTimeoutMs) / 1000.0)
        var counter = 0

        // Iterative DFS with caps. Stack holds (element, depth).
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        while let (el, depth) = stack.popLast() {
            if Task.isCancelled { fragment.truncated = true; break }
            if Date() >= deadline { fragment.truncated = true; break }
            if fragment.elements.count >= options.maxElements { fragment.truncated = true; break }

            fragment.scanned += 1

            let attrs = AXAttr.batch(el)
            let role = attrs.role ?? ""
            let subrole = attrs.subrole
            let text = Self.labelAndDescription(from: attrs)
            let identifier = attrs.identifier
            let enabled = attrs.enabled ?? true
            let focused = attrs.focused ?? false
            let frame = attrs.frame

            if captureURL, fragment.url == nil, role == "AXWebArea" {
                if let raw = AXAttr.copy(el, "AXURL") {
                    if let nsurl = raw as? URL {
                        fragment.url = nsurl.absoluteString
                    } else if let s = raw as? String {
                        fragment.url = s
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
            let kept = AXFilter.keep(candidate, onScreenOnly: options.onScreenOnly, screenUnion: screenUnion)
                || Self.shouldKeepInChrome(scope: scope, role: role)
            if kept, let frame {
                counter += 1
                let id = "\(idPrefix)_\(counter)"
                let rawValue = AXAttr.displayValue(el)
                let value = Self.safeValue(for: attrs, raw: rawValue, label: text.label, description: text.description)
                let normalized = UINormalization.axRole(role, subrole: subrole)
                var metadata = normalized.1
                if let identifier { metadata["identifier"] = identifier }
                let node = UIElementNode(
                    id: id,
                    source: .ax,
                    scope: scope,
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
                fragment.elements.append(node)
                fragment.resolverMap[id] = el
                fragment.frameMap[id] = frame
                fragment.nodeMap[id] = node
            }

            if depth + 1 <= options.maxDepth {
                let kids = AXAttr.children(el)
                // Push in reverse so popLast() processes them in document order.
                for child in kids.reversed() {
                    stack.append((child, depth + 1))
                }
            }
        }

        return fragment
    }

    /// In the menu-bar / Dock scopes, the strict AXFilter is too aggressive: the
    /// Apple menu's AXMenuBarItem has no AXTitle (it's just the Apple icon) and
    /// the AXFilter rejects roles that aren't in its actionable set. Let
    /// the scope-aware caller keep menu-bar items and dock items unconditionally
    /// so the persona has at least the top-level chrome to point at.
    private static func shouldKeepInChrome(scope: UIElementScope, role: String) -> Bool {
        switch scope {
        case .menuBar:
            return role == "AXMenuBarItem" || role == "AXMenuItem"
        case .dock:
            // AXDockItem is the canonical Dock-item role.
            return role == "AXDockItem"
        case .appWindow, .systemUI:
            return false
        }
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
