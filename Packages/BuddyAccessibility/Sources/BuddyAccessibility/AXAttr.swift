import ApplicationServices
import CoreGraphics
import Foundation

public struct AXAttrBatch: Sendable {
    public var role: String?
    public var subrole: String?
    public var title: String?
    public var description: String?
    public var help: String?
    public var identifier: String?
    public var enabled: Bool?
    public var focused: Bool?
    public var frame: CGRect?

    public init(
        role: String? = nil,
        subrole: String? = nil,
        title: String? = nil,
        description: String? = nil,
        help: String? = nil,
        identifier: String? = nil,
        enabled: Bool? = nil,
        focused: Bool? = nil,
        frame: CGRect? = nil
    ) {
        self.role = role
        self.subrole = subrole
        self.title = title
        self.description = description
        self.help = help
        self.identifier = identifier
        self.enabled = enabled
        self.focused = focused
        self.frame = frame
    }
}

private func unpackPoint(_ raw: AnyObject?) -> CGPoint? {
    guard let raw else { return nil }
    let cf = raw as CFTypeRef
    guard CFGetTypeID(cf) == AXValueGetTypeID() else { return nil }
    let val = unsafeDowncast(cf, to: AXValue.self)
    guard AXValueGetType(val) == .cgPoint else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(val, .cgPoint, &point) else { return nil }
    return point
}

private func unpackSize(_ raw: AnyObject?) -> CGSize? {
    guard let raw else { return nil }
    let cf = raw as CFTypeRef
    guard CFGetTypeID(cf) == AXValueGetTypeID() else { return nil }
    let val = unsafeDowncast(cf, to: AXValue.self)
    guard AXValueGetType(val) == .cgSize else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(val, .cgSize, &size) else { return nil }
    return size
}

enum AXAttr {
    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return err == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let v = copy(element, attribute) else { return nil }
        return v as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let v = copy(element, attribute) else { return nil }
        return (v as? Bool) ?? ((v as? NSNumber)?.boolValue)
    }

    // AXValue → CGRect (kAXPositionAttribute + kAXSizeAttribute combined).
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let pos = copy(element, kAXPositionAttribute as String),
              let siz = copy(element, kAXSizeAttribute as String) else { return nil }
        guard let point = unpackPoint(pos), let size = unpackSize(siz) else { return nil }
        return CGRect(origin: point, size: size)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard err == .success, let arr = value as? [AXUIElement] else { return [] }
        return arr
    }

    static func setTimeout(_ element: AXUIElement, seconds: Float) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    // Best-effort short value: prefer a String AXValue, else stringified number/bool, else nil.
    // Truncates long strings; we don't ship novel-length form values to Gemini.
    static func displayValue(_ element: AXUIElement, maxLength: Int = 200) -> String? {
        guard let raw = copy(element, kAXValueAttribute as String) else { return nil }
        let s: String
        if let str = raw as? String { s = str }
        else if let n = raw as? NSNumber { s = n.stringValue }
        else { return nil }
        if s.count > maxLength {
            return String(s.prefix(maxLength)) + "…"
        }
        return s
    }

    public static func batch(_ el: AXUIElement) -> AXAttrBatch {
        let attrs: CFArray = ([
            kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute,
            kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute,
            kAXEnabledAttribute, kAXFocusedAttribute,
            kAXPositionAttribute, kAXSizeAttribute,
        ] as [CFString]) as CFArray
        var raw: CFArray?
        let err = AXUIElementCopyMultipleAttributeValues(el, attrs, AXCopyMultipleAttributeOptions(rawValue: 0), &raw)
        guard err == .success, let arr = raw as? [AnyObject], arr.count == 10 else {
            return AXAttrBatch(role: nil, subrole: nil, title: nil,
                               description: nil, help: nil, identifier: nil,
                               enabled: nil, focused: nil, frame: nil)
        }
        func str(_ i: Int) -> String? {
            guard let s = arr[i] as? String, !s.isEmpty else { return nil }
            return s
        }
        func bool(_ i: Int) -> Bool? { arr[i] as? Bool }
        let pt = unpackPoint(arr[8])
        let sz = unpackSize(arr[9])
        let frame: CGRect? = (pt != nil && sz != nil) ? CGRect(origin: pt!, size: sz!) : nil
        return AXAttrBatch(role: str(0), subrole: str(1), title: str(2),
                           description: str(3), help: str(4), identifier: str(5),
                           enabled: bool(6), focused: bool(7), frame: frame)
    }
}
