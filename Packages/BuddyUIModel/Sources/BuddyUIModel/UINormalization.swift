import Foundation

public enum UINormalization {
    public static func cleanText(_ value: String?, maxLength: Int = 200) -> String? {
        guard let value else { return nil }
        guard maxLength > 0 else { return nil }
        let collapsed = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count > maxLength {
            guard maxLength > 3 else { return String(collapsed.prefix(maxLength)) }
            return String(collapsed.prefix(maxLength - 3)) + "..."
        }
        return collapsed
    }

    public static func axRole(_ role: String?, subrole: String? = nil) -> (UIElementRole, [String: String]) {
        let raw = role ?? ""
        let normalized: UIElementRole = switch raw {
        case "AXButton": .button
        case "AXLink": .link
        case "AXTextField", "AXTextArea": .textField
        case "AXCheckBox": .checkbox
        case "AXRadioButton": .radio
        case "AXPopUpButton", "AXComboBox": .combobox
        case "AXMenuItem": .menuItem
        case "AXTabGroup", "AXTabButton": .tab
        case "AXStaticText": .text
        case "AXHeading": .heading
        case "AXImage": .image
        case "AXGroup": .group
        case "AXWebArea": .webArea
        default: .generic
        }
        var metadata: [String: String] = [:]
        if !raw.isEmpty, normalized == .generic { metadata["original_role"] = raw }
        if let subrole, !subrole.isEmpty { metadata["subrole"] = subrole }
        return (normalized, metadata)
    }

    public static func domRole(tag: String, role: String?, type: String? = nil) -> (UIElementRole, [String: String]) {
        let lowerTag = tag.lowercased()
        let lowerRole = role?.lowercased()
        let lowerType = type?.lowercased()
        let semantic = lowerRole.flatMap(roleFromDOMSemantic)
            ?? roleFromDOMTag(lowerTag, type: lowerType)
            ?? .generic

        var metadata: [String: String] = ["tag": lowerTag]
        if let role, !role.isEmpty, semantic == .generic { metadata["original_role"] = role }
        if let lowerType, !lowerType.isEmpty { metadata["input_type"] = lowerType }
        return (semantic, metadata)
    }

    public static func isSensitiveField(
        role: UIElementRole,
        label: String?,
        description: String?,
        placeholder: String?,
        inputType: String?,
        name: String?,
        id: String?
    ) -> Bool {
        if role == .passwordField { return true }
        if let inputType = inputType?.lowercased(), ["password", "email", "tel"].contains(inputType) {
            return true
        }
        let haystack = [label, description, placeholder, name, id]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let sensitiveNeedles = [
            "password", "пароль", "parol", "pin", "пин", "otp", "one-time", "code", "код", "kod",
            "stir", "inn", "инн", "tax", "налог", "soliq", "card", "карта", "karta", "bank",
            "account", "счет", "hisob", "passport", "паспорт", "id number", "email", "phone", "телефон"
        ]
        return sensitiveNeedles.contains { haystack.contains($0) }
    }

    private static func roleFromDOMSemantic(_ role: String) -> UIElementRole? {
        switch role {
        case "button": .button
        case "link": .link
        case "textbox": .textField
        case "checkbox": .checkbox
        case "radio": .radio
        case "tab": .tab
        case "menuitem", "menuitemcheckbox", "menuitemradio": .menuItem
        case "option": .option
        case "switch": .switchControl
        case "combobox": .combobox
        case "searchbox": .searchbox
        case "slider": .slider
        case "spinbutton": .spinbutton
        case "heading": .heading
        case "img", "image": .image
        case "group": .group
        default: nil
        }
    }

    private static func roleFromDOMTag(_ tag: String, type: String?) -> UIElementRole? {
        switch tag {
        case "button": .button
        case "a": .link
        case "textarea": .textField
        case "select": .combobox
        case "h1", "h2", "h3", "h4", "h5", "h6": .heading
        case "label", "legend", "caption", "figcaption", "summary": .label
        case "img": .image
        case "input":
            switch type ?? "text" {
            case "password": .passwordField
            case "checkbox": .checkbox
            case "radio": .radio
            case "search": .searchbox
            case "range": .slider
            case "number": .spinbutton
            case "button", "submit", "reset": .button
            default: .textField
            }
        default:
            nil
        }
    }
}
