import Foundation

/// Best-effort `.gitignore` evaluator. Supports comments, negation, anchored
/// patterns, `*`, `**`, `?`, character classes and directory-only patterns.
/// Used by `fs_grep` to skip ignored files.
final class GitIgnoreMatcher {
    private struct Rule {
        var base: String
        var regex: NSRegularExpression
        var negated: Bool
        var directoryOnly: Bool
        var anchored: Bool
    }

    private let root: URL
    private var cache: [String: [Rule]] = [:]

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    func isIgnored(relativePath: String, isDirectory: Bool) -> Bool {
        let path = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return false }

        var ignored = false
        for directory in ancestorDirectories(for: path) {
            for rule in rules(in: directory) {
                let relative = relative(path, to: directory)
                guard !relative.isEmpty else { continue }
                if rule.directoryOnly && !isDirectory {
                    // A directory-only rule still ignores everything below it.
                    if !matchesDescendant(rule: rule, path: relative) { continue }
                } else if !matches(rule: rule, path: relative) {
                    continue
                }
                ignored = !rule.negated
            }
        }
        return ignored
    }

    private func ancestorDirectories(for path: String) -> [String] {
        var result: [String] = [""]
        let components = path.split(separator: "/").dropLast()
        var current = ""
        for component in components {
            current = current.isEmpty ? String(component) : current + "/" + component
            result.append(current)
        }
        return result
    }

    private func relative(_ path: String, to directory: String) -> String {
        guard !directory.isEmpty else { return path }
        let prefix = directory + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    private func rules(in directory: String) -> [Rule] {
        if let cached = cache[directory] { return cached }
        var loaded: [Rule] = []
        let url = root.appendingPathComponent(directory.isEmpty ? ".gitignore" : directory + "/.gitignore")
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            for rawLine in text.components(separatedBy: .newlines) {
                if let rule = Self.parse(rawLine, base: directory) {
                    loaded.append(rule)
                }
            }
        }
        cache[directory] = loaded
        return loaded
    }

    private func matches(rule: Rule, path: String) -> Bool {
        let candidate = rule.anchored ? path : path.split(separator: "/").last.map(String.init) ?? path
        if !rule.anchored && !rule.directoryOnly {
            // A non-anchored pattern also matches any parent directory component.
            let range = NSRange(candidate.startIndex..., in: candidate)
            if rule.regex.firstMatch(in: candidate, range: range) != nil { return true }
            let components = path.split(separator: "/").map(String.init)
            return components.dropLast().contains { component in
                rule.regex.firstMatch(in: component, range: NSRange(component.startIndex..., in: component)) != nil
            }
        }
        let range = NSRange(candidate.startIndex..., in: candidate)
        return rule.regex.firstMatch(in: candidate, range: range) != nil
    }

    private func matchesDescendant(rule: Rule, path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return false }
        for index in 0..<components.count {
            let candidate = components[index]
            let range = NSRange(candidate.startIndex..., in: candidate)
            if rule.regex.firstMatch(in: candidate, range: range) != nil { return true }
        }
        return false
    }

    private static func parse(_ rawLine: String, base: String) -> Rule? {
        var line = rawLine
        if line.hasSuffix("\r") { line.removeLast() }
        if line.hasPrefix("\\#") {
            line.removeFirst()
        } else {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }
            line = trimmed
        }
        line = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }

        var negated = false
        if line.hasPrefix("!") {
            negated = true
            line.removeFirst()
        } else if line.hasPrefix("\\!") {
            line.removeFirst()
        }

        var directoryOnly = false
        if line.hasSuffix("/") {
            directoryOnly = true
            line.removeLast()
        }
        guard !line.isEmpty else { return nil }

        let anchored = line.hasPrefix("/") || line.dropFirst().contains("/")
        if line.hasPrefix("/") { line.removeFirst() }

        let pattern = globToRegex(line, anchored: anchored || line.contains("/"), directoryOnly: directoryOnly)
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return Rule(
            base: base,
            regex: regex,
            negated: negated,
            directoryOnly: directoryOnly,
            anchored: anchored || line.contains("/")
        )
    }

    private static func globToRegex(_ glob: String, anchored: Bool, directoryOnly: Bool) -> String {
        var regex = anchored ? "^" : ""
        var index = glob.startIndex
        while index < glob.endIndex {
            let character = glob[index]
            switch character {
            case "*":
                let next = glob.index(after: index)
                if next < glob.endIndex, glob[next] == "*" {
                    let after = glob.index(after: next)
                    if after < glob.endIndex, glob[after] == "/" {
                        regex += "(?:.*/)?"
                        index = after
                    } else {
                        regex += ".*"
                        index = next
                    }
                } else {
                    regex += "[^/]*"
                }
            case "?":
                regex += "[^/]"
            case "[":
                var set = "["
                var cursor = glob.index(after: index)
                if cursor < glob.endIndex, glob[cursor] == "!" {
                    set += "^"
                    cursor = glob.index(after: cursor)
                }
                while cursor < glob.endIndex, glob[cursor] != "]" {
                    let value = glob[cursor]
                    if value == "\\" || value == "]" {
                        set += "\\" + String(value)
                    } else {
                        set += String(value)
                    }
                    cursor = glob.index(after: cursor)
                }
                if cursor < glob.endIndex {
                    set += "]"
                    index = cursor
                    regex += set
                } else {
                    regex += "\\["
                }
            case ".", "+", "(", ")", "{", "}", "^", "$", "|", "\\":
                regex += "\\" + String(character)
            default:
                regex += String(character)
            }
            index = glob.index(after: index)
        }
        if anchored {
            regex += "$"
        } else {
            regex = "(?:^|.*/)" + regex + "$"
        }
        if directoryOnly {
            regex += "(?:/.*)?"
        }
        return regex
    }
}
