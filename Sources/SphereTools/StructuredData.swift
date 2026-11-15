import Foundation
import CoreFoundation
import SphereCore

/// Loads JSON, YAML or plist documents and resolves a small path selector such
/// as `dependencies[0].url`, `providers.deepseek.model` or `["my key"]`.
/// Plain text files can be sliced with `lines:10-40`.
enum StructuredData {
    static func load(url: URL, formatHint: String? = nil) throws -> (value: JSONValue, format: String) {
        let data = try Data(contentsOf: url)
        let hint = formatHint?.lowercased()
        let ext = url.pathExtension.lowercased()

        let format: String
        if let hint, ["json", "yaml", "yml", "plist", "text"].contains(hint) {
            format = hint == "yml" ? "yaml" : hint
        } else if ext == "json" {
            format = "json"
        } else if ext == "plist" {
            format = "plist"
        } else if ext == "yaml" || ext == "yml" {
            format = "yaml"
        } else {
            format = "auto"
        }

        switch format {
        case "json":
            return (try decodeJSON(data), "json")
        case "plist":
            return (try decodePlist(data), "plist")
        case "yaml":
            guard let text = String(data: data, encoding: .utf8) else {
                throw SphereError.protocolError("YAML file is not UTF-8")
            }
            var parser = YAMLParser(text: text)
            return (try parser.parse(), "yaml")
        case "text":
            throw SphereError.protocolError("use the lines:START-END selector for text files")
        default:
            if let value = try? decodeJSON(data) { return (value, "json") }
            if let value = try? decodePlist(data) { return (value, "plist") }
            if ext == "yaml" || ext == "yml" {
                if let text = String(data: data, encoding: .utf8) {
                    var parser = YAMLParser(text: text)
                    if let value = try? parser.parse() {
                        return (value, "yaml")
                    }
                }
            }
            throw SphereError.protocolError(
                "could not detect a JSON, YAML or plist document; use format, or select lines:START-END for text files"
            )
        }
    }

    static func select(_ value: JSONValue, selector: String) throws -> JSONValue {
        let tokens = try SelectorToken.parse(selector)
        if tokens.isEmpty { return value }
        return try resolve(value, tokens: tokens)
    }

    static func pretty(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let value):
            if value.rounded() == value { return String(Int64(value)) }
            return String(value)
        case .string(let value): return value
        case .array, .object:
            guard let data = try? JSONEncoder.pretty.encode(value),
                  let text = String(data: data, encoding: .utf8) else {
                return "<unencodable value>"
            }
            return text
        }
    }

    static func sliceLines(url: URL, selector: String) throws -> String {
        let body = selector.dropFirst("lines:".count)
        let parts = body.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]), start > 0, end >= start else {
            throw SphereError.protocolError("invalid line selector, expected lines:START-END")
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: .newlines)
        let from = min(start - 1, lines.count)
        let to = min(end, lines.count)
        guard from < to else { return "" }
        return lines[from..<to].enumerated().map { index, line in
            String(format: "%6d\t%@", from + index + 1, line)
        }.joined(separator: "\n")
    }

    private static func resolve(_ value: JSONValue, tokens: [SelectorToken]) throws -> JSONValue {
        guard let token = tokens.first else { return value }
        let rest = Array(tokens.dropFirst())
        switch token {
        case .key(let key):
            guard let child = value[key] else {
                throw SphereError.protocolError("selector key '\(key)' not found")
            }
            return try resolve(child, tokens: rest)
        case .index(let index):
            guard let array = value.arrayValue else {
                throw SphereError.protocolError("selector index [\(index)] applied to a non-array")
            }
            guard array.indices.contains(index) else {
                throw SphereError.protocolError("selector index [\(index)] out of bounds")
            }
            return try resolve(array[index], tokens: rest)
        case .wildcard:
            let children: [JSONValue]
            if let array = value.arrayValue {
                children = array
            } else if let object = value.objectValue {
                children = object.keys.sorted().compactMap { object[$0] }
            } else {
                throw SphereError.protocolError("wildcard applied to a scalar")
            }
            if rest.isEmpty { return .array(children) }
            return .array(try children.map { try resolve($0, tokens: rest) })
        }
    }

    private static func decodeJSON(_ data: Data) throws -> JSONValue {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try JSONValue(any: object)
    }

    private static func decodePlist(_ data: Data) throws -> JSONValue {
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try JSONValue(any: object)
    }
}

private enum SelectorToken {
    case key(String)
    case index(Int)
    case wildcard

    static func parse(_ selector: String) throws -> [SelectorToken] {
        var tokens: [SelectorToken] = []
        var index = selector.startIndex
        while index < selector.endIndex {
            let character = selector[index]
            if character == "." {
                index = selector.index(after: index)
                continue
            }
            if character == "[" {
                guard let close = selector[index...].firstIndex(of: "]") else {
                    throw SphereError.protocolError("unterminated selector bracket")
                }
                let raw = String(selector[selector.index(after: index)..<close]).trimmingCharacters(in: .whitespaces)
                if raw == "*" {
                    tokens.append(.wildcard)
                } else if raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 {
                    tokens.append(.key(String(raw.dropFirst().dropLast())))
                } else if let number = Int(raw) {
                    tokens.append(.index(number))
                } else if !raw.isEmpty {
                    tokens.append(.key(raw))
                }
                index = selector.index(after: close)
                continue
            }
            var end = index
            while end < selector.endIndex, selector[end] != ".", selector[end] != "[" {
                end = selector.index(after: end)
            }
            let key = String(selector[index..<end])
            if key == "*" {
                tokens.append(.wildcard)
            } else if !key.isEmpty {
                tokens.append(.key(key))
            }
            index = end
        }
        return tokens
    }
}

extension JSONValue {
    init(any value: Any) throws {
        switch value {
        case is NSNull:
            self = .null
        case let value as Bool:
            self = .bool(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as String:
            self = .string(value)
        case let value as [Any]:
            self = .array(try value.map { try JSONValue(any: $0) })
        case let value as [String: Any]:
            var object: [String: JSONValue] = [:]
            for (key, child) in value {
                object[key] = try JSONValue(any: child)
            }
            self = .object(object)
        case let value as Date:
            self = .string(ISO8601DateFormatter().string(from: value))
        case let value as Data:
            self = .string(value.base64EncodedString())
        default:
            self = .string(String(describing: value))
        }
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

/// Small YAML subset parser: block mappings/sequences, quoted and plain
/// scalars, inline JSON-like arrays and objects. Enough for configuration files.
struct YAMLParser {
    private struct Line {
        let indent: Int
        let text: String
    }

    private let lines: [Line]
    private var index = 0

    init(text: String) {
        var parsed: [Line] = []
        for raw in text.components(separatedBy: .newlines) {
            let withoutComment = Self.stripComment(raw)
            guard !withoutComment.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let indent = withoutComment.prefix { $0 == " " }.count
            parsed.append(Line(indent: indent, text: String(withoutComment.dropFirst(indent))))
        }
        self.lines = parsed
    }

    mutating func parse() throws -> JSONValue {
        guard !lines.isEmpty else { return .object([:]) }
        let value = try parseBlock(indent: lines[0].indent)
        return value
    }

    private mutating func parseBlock(indent: Int) throws -> JSONValue {
        guard index < lines.count else { return .null }
        if lines[index].text.hasPrefix("- ") || lines[index].text == "-" {
            return try parseSequence(indent: indent)
        }
        return try parseMapping(indent: indent)
    }

    private mutating func parseMapping(indent: Int) throws -> JSONValue {
        var result: [String: JSONValue] = [:]
        while index < lines.count {
            let line = lines[index]
            guard line.indent == indent, !line.text.hasPrefix("- ") else { break }
            guard let colon = line.text.firstIndex(of: ":") else {
                throw SphereError.protocolError("invalid YAML mapping line '\(line.text)'")
            }
            let key = String(line.text[..<colon]).trimmingCharacters(in: .whitespaces)
            let rest = String(line.text[line.text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            index += 1
            if rest.isEmpty {
                if index < lines.count, lines[index].indent > indent {
                    result[key] = try parseBlock(indent: lines[index].indent)
                } else {
                    result[key] = .null
                }
            } else {
                result[key] = Self.scalar(rest)
            }
        }
        return .object(result)
    }

    private mutating func parseSequence(indent: Int) throws -> JSONValue {
        var result: [JSONValue] = []
        while index < lines.count {
            let line = lines[index]
            guard line.indent == indent, line.text.hasPrefix("-") else { break }
            let rest = String(line.text.dropFirst()).trimmingCharacters(in: .whitespaces)
            index += 1
            if rest.isEmpty {
                if index < lines.count, lines[index].indent > indent {
                    result.append(try parseBlock(indent: lines[index].indent))
                } else {
                    result.append(.null)
                }
                continue
            }
            if let colon = rest.firstIndex(of: ":") {
                var object: [String: JSONValue] = [:]
                let key = String(rest[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(rest[rest.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                object[key] = value.isEmpty ? .null : Self.scalar(value)
                if index < lines.count, lines[index].indent > indent {
                    let nestedIndent = lines[index].indent
                    if let nested = try? parseMapping(indent: nestedIndent), case .object(let more) = nested {
                        object.merge(more) { current, _ in current }
                    }
                }
                result.append(.object(object))
            } else {
                result.append(Self.scalar(rest))
            }
        }
        return .array(result)
    }

    private static func scalar(_ raw: String) -> JSONValue {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            return .string(String(value.dropFirst().dropLast()))
        }
        if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
            return .string(String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'"))
        }
        switch value.lowercased() {
        case "null", "~": return .null
        case "true": return .bool(true)
        case "false": return .bool(false)
        default:
            if let number = Double(value) { return .number(number) }
            return .string(value)
        }
    }

    private static func stripComment(_ line: String) -> String {
        var inSingle = false
        var inDouble = false
        var previous: Character?
        for (offset, character) in line.enumerated() {
            if character == "'" && !inDouble { inSingle.toggle() }
            if character == "\"" && !inSingle && previous != "\\" { inDouble.toggle() }
            if character == "#" && !inSingle && !inDouble {
                if offset == 0 || line[line.index(line.startIndex, offsetBy: offset - 1)] == " " {
                    return String(line.prefix(offset))
                }
            }
            previous = character
        }
        return line
    }
}

/// Unified-diff applier used by `fs_edit` (mode `patch`). Supports multiple
/// hunks in one file; fails loudly when a hunk does not match.
enum UnifiedPatch {
    static func apply(_ patch: String, to original: String) throws -> (text: String, hunks: Int) {
        let hadTrailingNewline = original.hasSuffix("\n")
        var lines = original.components(separatedBy: "\n")
        if hadTrailingNewline, lines.last == "" { lines.removeLast() }
        let patchLines = patch.components(separatedBy: "\n")

        struct Hunk {
            var oldStart: Int
            var oldLines: [String]
            var newLines: [String]
        }

        var hunks: [Hunk] = []
        var current: Hunk?
        let header = try NSRegularExpression(pattern: "^@@ -(\\d+)(?:,\\d+)? \\+\\d+(?:,\\d+)? @@")

        for line in patchLines {
            if line.hasPrefix("@@") {
                if let current { hunks.append(current) }
                guard let match = header.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let range = Range(match.range(at: 1), in: line),
                      let start = Int(line[range]) else {
                    throw SphereError.protocolError("invalid patch hunk header '\(line)'")
                }
                current = Hunk(oldStart: max(start - 1, 0), oldLines: [], newLines: [])
                continue
            }
            guard var hunk = current else { continue }
            if line.hasPrefix(" ") {
                let value = String(line.dropFirst())
                hunk.oldLines.append(value)
                hunk.newLines.append(value)
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                hunk.oldLines.append(String(line.dropFirst()))
            } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
                hunk.newLines.append(String(line.dropFirst()))
            } else if line.hasPrefix("\\") {
                continue
            }
            current = hunk
        }
        if let current { hunks.append(current) }

        var cursor = 0
        var output: [String] = []
        for hunk in hunks {
            let matchIndex = find(hunk.oldLines, in: lines, near: max(hunk.oldStart, cursor))
            guard let matchIndex else {
                throw SphereError.protocolError("patch hunk at line \(hunk.oldStart + 1) does not match the file")
            }
            if matchIndex > cursor {
                output.append(contentsOf: lines[cursor..<matchIndex])
            }
            output.append(contentsOf: hunk.newLines)
            cursor = matchIndex + hunk.oldLines.count
        }
        if cursor < lines.count {
            output.append(contentsOf: lines[cursor...])
        }
        var text = output.joined(separator: "\n")
        if hadTrailingNewline { text += "\n" }
        return (text, hunks.count)
    }

    private static func find(_ needle: [String], in haystack: [String], near index: Int) -> Int? {
        if needle.isEmpty { return min(index, haystack.count) }
        guard needle.count <= haystack.count else { return nil }
        let upper = haystack.count - needle.count
        let start = min(max(index, 0), upper)
        if Array(haystack[start..<(start + needle.count)]) == needle { return start }
        for offset in 1...max(upper, 1) {
            let before = start - offset
            if before >= 0, Array(haystack[before..<(before + needle.count)]) == needle { return before }
            let after = start + offset
            if after <= upper, Array(haystack[after..<(after + needle.count)]) == needle { return after }
            if before < 0 && after > upper { break }
        }
        return nil
    }
}
