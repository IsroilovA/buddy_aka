import CoreGraphics
import Foundation

public struct UISnapshot: Codable, Sendable, Equatable {
    public var app: String?
    public var windowTitle: String?
    public var url: String?
    public var elements: [UIElementNode]
    public var stats: UISnapshotStats

    enum CodingKeys: String, CodingKey {
        case app
        case windowTitle = "window_title"
        case url
        case elements
        case stats
    }

    public init(
        app: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        elements: [UIElementNode] = [],
        stats: UISnapshotStats = .init()
    ) {
        self.app = app
        self.windowTitle = windowTitle
        self.url = url
        self.elements = elements
        self.stats = stats
    }
}

public struct UIElementNode: Codable, Sendable, Equatable {
    public var id: String
    public var source: UIElementSource
    public var scope: UIElementScope
    public var role: UIElementRole
    public var label: String?
    public var description: String?
    public var value: String?
    public var hasValue: Bool
    public var enabled: Bool
    public var focused: Bool
    public var frame: UIFrame
    public var metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, source, scope, role, label, description, value, enabled, focused, frame, metadata
        case hasValue = "has_value"
    }

    public init(
        id: String,
        source: UIElementSource,
        scope: UIElementScope = .appWindow,
        role: UIElementRole,
        label: String? = nil,
        description: String? = nil,
        value: String? = nil,
        hasValue: Bool = false,
        enabled: Bool,
        focused: Bool,
        frame: UIFrame,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.source = source
        self.scope = scope
        self.role = role
        self.label = label
        self.description = description
        self.value = value
        self.hasValue = hasValue
        self.enabled = enabled
        self.focused = focused
        self.frame = frame
        self.metadata = metadata
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.source = try c.decode(UIElementSource.self, forKey: .source)
        // Codable default: pre-scope snapshots decode as appWindow.
        self.scope = (try? c.decode(UIElementScope.self, forKey: .scope)) ?? .appWindow
        self.role = try c.decode(UIElementRole.self, forKey: .role)
        self.label = try c.decodeIfPresent(String.self, forKey: .label)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.value = try c.decodeIfPresent(String.self, forKey: .value)
        self.hasValue = (try? c.decode(Bool.self, forKey: .hasValue)) ?? false
        self.enabled = try c.decode(Bool.self, forKey: .enabled)
        self.focused = try c.decode(Bool.self, forKey: .focused)
        self.frame = try c.decode(UIFrame.self, forKey: .frame)
        self.metadata = (try? c.decode([String: String].self, forKey: .metadata)) ?? [:]
    }
}

public struct UIFrame: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public init(_ rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.w = Double(rect.size.width)
        self.h = Double(rect.size.height)
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }
}

public struct UISnapshotStats: Codable, Sendable, Equatable {
    public var scanned: Int
    public var kept: Int
    public var truncated: Bool
    public var elapsedMs: Int

    enum CodingKeys: String, CodingKey {
        case scanned, kept, truncated
        case elapsedMs = "elapsed_ms"
    }

    public init(scanned: Int = 0, kept: Int = 0, truncated: Bool = false, elapsedMs: Int = 0) {
        self.scanned = scanned
        self.kept = kept
        self.truncated = truncated
        self.elapsedMs = elapsedMs
    }
}

public enum UIElementSource: String, Codable, Sendable, Equatable {
    case ax
    case dom
    case vision
}

/// Where on screen the element lives. Orthogonal to `UIElementSource`.
/// `appWindow` means "inside the frontmost app's focused window". The other
/// three describe the always-on-screen chrome that exists outside that window.
public enum UIElementScope: String, Codable, Sendable, Equatable {
    case appWindow = "app_window"
    case menuBar = "menu_bar"
    case dock
    case systemUI = "system_ui"
}

public enum UIElementRole: String, Codable, Sendable, Equatable {
    case button
    case link
    case textField = "text_field"
    case passwordField = "password_field"
    case checkbox
    case radio
    case tab
    case menuItem = "menu_item"
    case option
    case switchControl = "switch"
    case combobox
    case searchbox
    case slider
    case spinbutton
    case heading
    case label
    case text
    case image
    case group
    case webArea = "web_area"
    case generic
}

public protocol UISnapshotResolving: AnyObject {
    var ids: [String] { get }
    func hasElement(_ id: String) -> Bool
    func node(for id: String) -> UIElementNode?
    func liveFrame(for id: String) -> CGRect?
}
