import Foundation

/// Tiny YAML reader for the lesson-frontmatter subset:
/// - flat key: scalar
/// - key:
///     - list item
///     - list item
/// - key:
///     subkey: value
/// - block scalars via `|` (literal, preserve newlines) and `>` (folded → space).
/// - inline flow `{ key: value }` (one level).
///
/// Not a general YAML parser. Throws `YAMLError` on malformed input.
public enum YAMLLite {
    public enum YAMLValue: @unchecked Sendable {
        case scalar(String)
        case list([YAMLValue])
        case dict([(String, YAMLValue)])

        public var asString: String? {
            if case .scalar(let s) = self { return s }
            return nil
        }

        public var asList: [YAMLValue]? {
            if case .list(let l) = self { return l }
            return nil
        }

        public var asDict: [(String, YAMLValue)]? {
            if case .dict(let d) = self { return d }
            return nil
        }

        public func get(_ key: String) -> YAMLValue? {
            guard case .dict(let pairs) = self else { return nil }
            return pairs.first { $0.0 == key }?.1
        }

        public func string(_ key: String) -> String? { get(key)?.asString }
    }

    public struct YAMLError: Error, CustomStringConvertible {
        public let line: Int
        public let message: String
        public var description: String { "YAML line \(line): \(message)" }
    }

    public static func parse(_ source: String) throws -> YAMLValue {
        let raw = source.components(separatedBy: "\n")
        // Drop trailing blank lines.
        var lines: [(idx: Int, indent: Int, text: String)] = []
        for (i, line) in raw.enumerated() {
            // Strip trailing CR if any (Windows newlines).
            let stripped = line.hasSuffix("\r") ? String(line.dropLast()) : line
            let trimmed = stripped.drop(while: { $0 == " " })
            // Skip blank or comment-only lines.
            if trimmed.isEmpty { continue }
            if trimmed.first == "#" { continue }
            let indent = stripped.count - trimmed.count
            lines.append((idx: i + 1, indent: indent, text: String(stripped)))
        }
        var index = 0
        let (value, _) = try parseBlock(lines: lines, index: &index, baseIndent: 0)
        return value
    }

    private static func parseBlock(
        lines: [(idx: Int, indent: Int, text: String)],
        index: inout Int,
        baseIndent: Int
    ) throws -> (YAMLValue, Bool) {
        guard index < lines.count else { return (.dict([]), false) }
        let first = lines[index]
        let trimmed = first.text.drop(while: { $0 == " " })
        _ = baseIndent
        if trimmed.hasPrefix("- ") || trimmed == "-" {
            return (try parseList(lines: lines, index: &index, baseIndent: first.indent), true)
        } else {
            return (try parseDict(lines: lines, index: &index, baseIndent: first.indent), true)
        }
    }

    private static func parseDict(
        lines: [(idx: Int, indent: Int, text: String)],
        index: inout Int,
        baseIndent: Int
    ) throws -> YAMLValue {
        var pairs: [(String, YAMLValue)] = []
        while index < lines.count {
            let line = lines[index]
            if line.indent < baseIndent { break }
            if line.indent > baseIndent {
                throw YAMLError(line: line.idx, message: "unexpected indent")
            }
            let body = String(line.text.drop(while: { $0 == " " }))
            // Lists at the same indent as the dict are not allowed; that would be a list, not a dict.
            if body.hasPrefix("- ") {
                throw YAMLError(line: line.idx, message: "list marker inside dict at same indent")
            }
            guard let colon = body.firstIndex(of: ":") else {
                throw YAMLError(line: line.idx, message: "expected ':' in '\(body)'")
            }
            let key = String(body[..<colon]).trimmingCharacters(in: .whitespaces)
            let after = body.index(after: colon)
            let valuePart = String(body[after...]).trimmingCharacters(in: .whitespaces)
            index += 1

            if valuePart.isEmpty {
                // Children block or empty value.
                if index < lines.count && lines[index].indent > baseIndent {
                    let childIndent = lines[index].indent
                    let childFirst = String(lines[index].text.drop(while: { $0 == " " }))
                    if childFirst.hasPrefix("- ") {
                        pairs.append((key, try parseList(lines: lines, index: &index, baseIndent: childIndent)))
                    } else {
                        pairs.append((key, try parseDict(lines: lines, index: &index, baseIndent: childIndent)))
                    }
                } else {
                    pairs.append((key, .scalar("")))
                }
            } else if valuePart == "|" || valuePart == ">" || valuePart == "|-" || valuePart == ">-" {
                let value = try parseBlockScalar(
                    style: valuePart,
                    lines: lines,
                    index: &index,
                    baseIndent: baseIndent
                )
                pairs.append((key, .scalar(value)))
            } else if valuePart.first == "{" {
                pairs.append((key, try parseFlowMap(valuePart, line: line.idx)))
            } else if valuePart.first == "[" {
                pairs.append((key, try parseFlowList(valuePart, line: line.idx)))
            } else {
                pairs.append((key, .scalar(stripQuotes(valuePart))))
            }
        }
        return .dict(pairs)
    }

    private static func parseList(
        lines: [(idx: Int, indent: Int, text: String)],
        index: inout Int,
        baseIndent: Int
    ) throws -> YAMLValue {
        var items: [YAMLValue] = []
        while index < lines.count {
            let line = lines[index]
            if line.indent < baseIndent { break }
            if line.indent > baseIndent {
                throw YAMLError(line: line.idx, message: "unexpected indent in list")
            }
            let body = String(line.text.drop(while: { $0 == " " }))
            guard body.hasPrefix("- ") || body == "-" else { break }
            let payload = body == "-" ? "" : String(body.dropFirst(2))
            index += 1
            if payload.isEmpty {
                // Nested.
                if index < lines.count && lines[index].indent > baseIndent {
                    let childIndent = lines[index].indent
                    let childFirst = String(lines[index].text.drop(while: { $0 == " " }))
                    if childFirst.hasPrefix("- ") {
                        items.append(try parseList(lines: lines, index: &index, baseIndent: childIndent))
                    } else {
                        items.append(try parseDict(lines: lines, index: &index, baseIndent: childIndent))
                    }
                } else {
                    items.append(.scalar(""))
                }
            } else if payload.contains(":") && payload.first != "{" {
                // Inline `- key: value` — possibly with subsequent siblings at indent+2.
                // Promote to dict by reparsing this line + any deeper-indented siblings.
                // We rewrite into a synthetic dict by treating the payload as an indent + 2 line.
                let pseudoIndent = baseIndent + 2
                var synthLines: [(idx: Int, indent: Int, text: String)] = [
                    (idx: line.idx, indent: pseudoIndent, text: String(repeating: " ", count: pseudoIndent) + payload)
                ]
                while index < lines.count {
                    let next = lines[index]
                    if next.indent <= baseIndent { break }
                    synthLines.append(next)
                    index += 1
                }
                var subIndex = 0
                items.append(try parseDict(lines: synthLines, index: &subIndex, baseIndent: pseudoIndent))
            } else if payload.first == "{" {
                items.append(try parseFlowMap(payload, line: line.idx))
            } else if payload.first == "[" {
                items.append(try parseFlowList(payload, line: line.idx))
            } else {
                items.append(.scalar(stripQuotes(payload)))
            }
        }
        return .list(items)
    }

    private static func parseBlockScalar(
        style: String,
        lines: [(idx: Int, indent: Int, text: String)],
        index: inout Int,
        baseIndent: Int
    ) throws -> String {
        var pieces: [String] = []
        let chomp = style.hasSuffix("-")
        let folded = style.first == ">"
        while index < lines.count {
            let line = lines[index]
            if line.indent <= baseIndent { break }
            let payload = String(line.text.drop(while: { $0 == " " }))
            pieces.append(payload)
            index += 1
        }
        let joined: String
        if folded {
            joined = pieces.joined(separator: " ")
        } else {
            joined = pieces.joined(separator: "\n")
        }
        if chomp {
            return joined.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
        }
        return joined
    }

    private static func parseFlowMap(_ text: String, line: Int) throws -> YAMLValue {
        // Expects `{ key: value, key: value }`. Single line only.
        var body = text.trimmingCharacters(in: .whitespaces)
        guard body.hasPrefix("{") && body.hasSuffix("}") else {
            throw YAMLError(line: line, message: "malformed flow map: \(text)")
        }
        body = String(body.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        if body.isEmpty { return .dict([]) }
        let parts = splitFlow(body)
        var pairs: [(String, YAMLValue)] = []
        for part in parts {
            guard let colon = part.firstIndex(of: ":") else { continue }
            let key = String(part[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(part[part.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            pairs.append((key, .scalar(stripQuotes(value))))
        }
        return .dict(pairs)
    }

    private static func parseFlowList(_ text: String, line: Int) throws -> YAMLValue {
        var body = text.trimmingCharacters(in: .whitespaces)
        guard body.hasPrefix("[") && body.hasSuffix("]") else {
            throw YAMLError(line: line, message: "malformed flow list: \(text)")
        }
        body = String(body.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        if body.isEmpty { return .list([]) }
        let parts = splitFlow(body)
        return .list(parts.map { .scalar(stripQuotes($0.trimmingCharacters(in: .whitespaces))) })
    }

    private static func splitFlow(_ text: String) -> [String] {
        var depth = 0
        var current = ""
        var out: [String] = []
        for ch in text {
            if ch == "{" || ch == "[" { depth += 1 }
            else if ch == "}" || ch == "]" { depth -= 1 }
            if ch == "," && depth == 0 {
                out.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private static func stripQuotes(_ s: String) -> String {
        guard s.count >= 2 else { return s }
        let first = s.first!
        let last = s.last!
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}
