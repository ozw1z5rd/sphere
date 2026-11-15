import Foundation
import SphereCore

/// Built-in, permission-aware filesystem tool. All access is funneled through
/// the `PermissionEngine` so grants and counters remain authoritative.
public final class FilesystemBroker: ToolProvider {
    public let moduleId = "sphere.filesystem"
    public let providerName = "Filesystem Broker"

    private let engine: PermissionEngine
    private let audit: AuditLog
    private let maximumReadBytes: Int
    private let maximumEditBytes: Int

    public init(
        engine: PermissionEngine,
        audit: AuditLog = AuditLog(),
        maximumReadBytes: Int = 2_000_000,
        maximumEditBytes: Int = 5_000_000
    ) {
        self.engine = engine
        self.audit = audit
        self.maximumReadBytes = maximumReadBytes
        self.maximumEditBytes = maximumEditBytes
    }

    public func definitions() -> [ToolDefinition] {
        [
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "fs_read"),
                originalName: "fs_read",
                moduleId: moduleId,
                description: "Read a UTF-8 text file from a granted path. Optional start_line/end_line slice the file (1-based, inclusive).",
                inputSchema: ToolSchemas.object(properties: [
                    "path": ToolSchemas.string(),
                    "start_line": ToolSchemas.integer("First line to return (1-based)."),
                    "end_line": ToolSchemas.integer("Last line to return (1-based, inclusive)."),
                ], required: ["path"])
            ),
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "fs_write"),
                originalName: "fs_write",
                moduleId: moduleId,
                description: "Write UTF-8 text to a path granted in read-write mode.",
                inputSchema: ToolSchemas.object(properties: [
                    "path": ToolSchemas.string(),
                    "content": ToolSchemas.string(),
                ], required: ["path", "content"])
            ),
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "fs_list"),
                originalName: "fs_list",
                moduleId: moduleId,
                description: "List the entries of a granted directory.",
                inputSchema: ToolSchemas.object(properties: [
                    "path": ToolSchemas.string(),
                ], required: ["path"])
            ),
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "fs_glob"),
                originalName: "fs_glob",
                moduleId: moduleId,
                description: "Find files under a granted directory matching a glob pattern (supports *, ?, **).",
                inputSchema: ToolSchemas.object(properties: [
                    "path": ToolSchemas.string(),
                    "pattern": ToolSchemas.string(),
                ], required: ["path", "pattern"])
            ),
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "fs_grep"),
                originalName: "fs_grep",
                moduleId: moduleId,
                description: "Search text files under a granted directory with a regular expression. Skips binary files (and says so), respects .gitignore by default, supports context lines and counts.",
                inputSchema: ToolSchemas.object(properties: [
                    "path": ToolSchemas.string(),
                    "pattern": ToolSchemas.string(),
                    "include": ToolSchemas.string("Optional glob filter, e.g. **/*.swift."),
                    "context": ToolSchemas.integer("Context lines before/after each match (0-5)."),
                    "count_only": ToolSchemas.boolean("Return per-file match counts instead of matching lines."),
                    "max_results": ToolSchemas.integer("Maximum matching lines (default 200, max 500)."),
                    "respect_gitignore": ToolSchemas.boolean("Skip paths ignored by .gitignore (default true)."),
                ], required: ["path", "pattern"])
            ),
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "fs_stat"),
                originalName: "fs_stat",
                moduleId: moduleId,
                description: "Stat a granted path: size, mtime, POSIX mode, type and file kind sniffed from magic bytes.",
                inputSchema: ToolSchemas.object(properties: [
                    "path": ToolSchemas.string(),
                ], required: ["path"])
            ),
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "fs_read_bytes"),
                originalName: "fs_read_bytes",
                moduleId: moduleId,
                description: "Read a small binary slice of a granted file (max 4096 bytes) and return hex and/or base64.",
                inputSchema: ToolSchemas.object(properties: [
                    "path": ToolSchemas.string(),
                    "offset": ToolSchemas.integer("Byte offset (default 0)."),
                    "length": ToolSchemas.integer("Bytes to read (default/max 4096)."),
                    "encoding": ToolSchemas.choice(["hex", "base64", "both"], "Output encoding (default both)."),
                ], required: ["path"])
            ),
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "fs_edit"),
                originalName: "fs_edit",
                moduleId: moduleId,
                description: "Edit a granted file by search/replace (`old`/`new`) or by applying a unified diff (`patch`).",
                inputSchema: ToolSchemas.object(properties: [
                    "path": ToolSchemas.string(),
                    "mode": ToolSchemas.choice(["replace", "patch"], "Edit mode (default replace)."),
                    "old": ToolSchemas.string("Text to search for in replace mode."),
                    "new": ToolSchemas.string("Replacement text in replace mode."),
                    "all": ToolSchemas.boolean("Replace every occurrence (default false)."),
                    "patch": ToolSchemas.string("Unified diff text in patch mode."),
                ], required: ["path"])
            ),
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "fs_select"),
                originalName: "fs_select",
                moduleId: moduleId,
                description: "Read a JSON/YAML/plist value with a path selector (e.g. dependencies[0].url) instead of the whole document. Text files support lines:START-END.",
                inputSchema: ToolSchemas.object(properties: [
                    "path": ToolSchemas.string(),
                    "selector": ToolSchemas.string("Dotted/bracket path, or lines:START-END for text."),
                    "format": ToolSchemas.choice(["auto", "json", "yaml", "plist", "text"], "Format hint (default auto)."),
                ], required: ["path", "selector"])
            ),
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "image_inspect"),
                originalName: "image_inspect",
                moduleId: moduleId,
                description: "Describe an image: format, dimensions, DPI, minimal EXIF and an optional PNG thumbnail.",
                inputSchema: ToolSchemas.object(properties: [
                    "path": ToolSchemas.string(),
                    "thumbnail": ToolSchemas.boolean("Include a base64 PNG thumbnail (default false)."),
                    "thumbnail_size": ToolSchemas.integer("Max thumbnail pixel size (default 256, max 512)."),
                ], required: ["path"])
            ),
        ]
    }

    public func invoke(tool: String, arguments: JSONValue) async throws -> ToolOutcome {
        switch tool {
        case "fs_read": return try read(arguments)
        case "fs_write": return try write(arguments)
        case "fs_list": return try list(arguments)
        case "fs_glob": return try glob(arguments)
        case "fs_grep": return try grep(arguments)
        case "fs_stat": return try stat(arguments)
        case "fs_read_bytes": return try readBytes(arguments)
        case "fs_edit": return try edit(arguments)
        case "fs_select": return try select(arguments)
        case "image_inspect": return try imageInspect(arguments)
        default: throw SphereError.protocolError("unknown filesystem tool '\(tool)'")
        }
    }

    // MARK: - Operations

    private func read(_ arguments: JSONValue) throws -> ToolOutcome {
        let path = try requiredString("path", in: arguments)
        _ = try engine.require(moduleId: moduleId, path: path, operation: .read)
        let url = URL(fileURLWithPath: PathPolicy.normalize(path))
        let data = try Data(contentsOf: url)
        guard data.count <= maximumReadBytes else {
            return ToolOutcome(
                text: "File is larger than \(maximumReadBytes) bytes; refusing to read.",
                isError: true
            )
        }
        var text = String(data: data, encoding: .utf8) ?? "<binary file: \(data.count) bytes>"
        if let start = arguments["start_line"]?.numberValue.map(Int.init),
           let end = arguments["end_line"]?.numberValue.map(Int.init) {
            text = Self.lineSlice(text, start: start, end: end)
        }
        audit.write("filesystem", "read \(url.path) (\(data.count) bytes)")
        return ToolOutcome(text: text)
    }

    private func write(_ arguments: JSONValue) throws -> ToolOutcome {
        let path = try requiredString("path", in: arguments)
        let content = try requiredString("content", in: arguments)
        _ = try engine.require(moduleId: moduleId, path: path, operation: .write)
        let url = URL(fileURLWithPath: PathPolicy.normalize(path))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url, options: .atomic)
        audit.write("filesystem", "write \(url.path)")
        return ToolOutcome(text: "Wrote \(content.utf8.count) bytes to \(url.path)")
    }

    private func list(_ arguments: JSONValue) throws -> ToolOutcome {
        let path = try requiredString("path", in: arguments)
        _ = try engine.require(moduleId: moduleId, path: path, operation: .list)
        let url = URL(fileURLWithPath: PathPolicy.normalize(path))
        let entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])
        let lines = entries.map { entry -> String in
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return (isDirectory ? "d " : "- ") + entry.lastPathComponent
        }.sorted()
        return ToolOutcome(text: lines.joined(separator: "\n"))
    }

    private func glob(_ arguments: JSONValue) throws -> ToolOutcome {
        let path = try requiredString("path", in: arguments)
        let pattern = try requiredString("pattern", in: arguments)
        let grant = try engine.require(moduleId: moduleId, path: path, operation: .glob)
        let root = URL(fileURLWithPath: PathPolicy.normalize(path))
        let regex = try Self.globRegex(pattern)
        var matches: [String] = []

        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let fileURL as URL in enumerator {
                let relative = Self.relativePath(fileURL, root: root)
                if regex.firstMatch(in: relative, range: NSRange(relative.startIndex..., in: relative)) != nil {
                    matches.append(relative)
                }
                if matches.count >= 500 { break }
            }
        }
        audit.write("filesystem", "glob \(root.path) '\(pattern)' -> \(matches.count) matches (grant \(grant.id))")
        return ToolOutcome(text: matches.sorted().joined(separator: "\n"))
    }

    private func grep(_ arguments: JSONValue) throws -> ToolOutcome {
        let path = try requiredString("path", in: arguments)
        let pattern = try requiredString("pattern", in: arguments)
        let include = arguments["include"]?.stringValue
        let contextLines = min(max(arguments["context"]?.numberValue.map(Int.init) ?? 0, 0), 5)
        let countOnly = arguments["count_only"]?.boolValue ?? false
        let maxResults = min(max(arguments["max_results"]?.numberValue.map(Int.init) ?? 200, 1), 500)
        let respectIgnore = arguments["respect_gitignore"]?.boolValue ?? true
        let grant = try engine.require(moduleId: moduleId, path: path, operation: .grep)
        let root = URL(fileURLWithPath: PathPolicy.normalize(path))
        let regex = try NSRegularExpression(pattern: pattern)
        let includeRegex = try include.map(Self.globRegex)
        let ignore = respectIgnore ? GitIgnoreMatcher(root: root) : nil

        var output: [String] = []
        var totalMatches = 0
        var filesMatched = 0
        var skippedBinary: [String] = []
        var skippedCount = 0
        var visited = 0

        if let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        ) {
            for case let fileURL as URL in enumerator {
                let relative = Self.relativePath(fileURL, root: root)
                let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
                if values?.isDirectory == true {
                    if fileURL.lastPathComponent == ".git" || ignore?.isIgnored(relativePath: relative, isDirectory: true) == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard values?.isRegularFile == true else { continue }
                if ignore?.isIgnored(relativePath: relative, isDirectory: false) == true { continue }
                if let includeRegex,
                   includeRegex.firstMatch(in: relative, range: NSRange(relative.startIndex..., in: relative)) == nil {
                    continue
                }
                let size = values?.fileSize ?? 0
                guard size > 0, size < maximumReadBytes else { continue }
                visited += 1

                let sniffed = FileSniffer.sniff(fileAt: fileURL)
                guard !sniffed.isBinary else {
                    skippedCount += 1
                    if skippedBinary.count < 20 { skippedBinary.append(relative) }
                    continue
                }
                guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    skippedCount += 1
                    if skippedBinary.count < 20 { skippedBinary.append(relative) }
                    continue
                }
                let lines = text.components(separatedBy: .newlines)
                var matches: [Int] = []
                for (index, line) in lines.enumerated() {
                    if regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                        matches.append(index)
                    }
                }
                guard !matches.isEmpty else { continue }
                filesMatched += 1
                totalMatches += matches.count

                if countOnly {
                    output.append("\(relative): \(matches.count)")
                    if totalMatches >= maxResults { break }
                    continue
                }

                var windows: [ClosedRange<Int>] = []
                for match in matches {
                    let lower = max(match - contextLines, 0)
                    let upper = min(match + contextLines, lines.count - 1)
                    if let last = windows.last, lower <= last.upperBound + 1 {
                        windows[windows.count - 1] = last.lowerBound...max(last.upperBound, upper)
                    } else {
                        windows.append(lower...upper)
                    }
                }
                var emitted = 0
                for window in windows {
                    if emitted > 0 { output.append("--") }
                    for index in window {
                        if totalMatches > 0 && emitted >= maxResults { break }
                        let isMatch = matches.contains(index)
                        let separator = isMatch ? ":" : "-"
                        let marker = isMatch ? ":" : "-"
                        output.append("\(relative)\(separator)\(index + 1)\(marker) \(lines[index])")
                        if isMatch {
                            emitted += 1
                            if emitted >= maxResults { break }
                        }
                    }
                    if emitted >= maxResults { break }
                }
                if totalMatches >= maxResults { break }
            }
        }

        audit.write(
            "filesystem",
            "grep \(root.path) '\(pattern)' -> \(totalMatches) matches in \(filesMatched) files, \(skippedCount) skipped (grant \(grant.id))"
        )

        var result = output
        if countOnly && !result.isEmpty {
            result.append("")
            result.append("total: \(totalMatches) matches in \(filesMatched) files")
        }
        if skippedCount > 0 {
            result.append("")
            result.append("skipped \(skippedCount) binary/non-UTF8 file(s):")
            result.append(contentsOf: skippedBinary.map { "  \($0)" })
            if skippedCount > skippedBinary.count { result.append("  …") }
        }
        if totalMatches == 0 {
            let prefix = "No text matches for '\(pattern)' (\(visited) file(s) searched)"
            result.insert(skippedCount > 0 ? "\(prefix), \(skippedCount) skipped" : prefix, at: 0)
        }
        if totalMatches >= maxResults && !countOnly {
            result.append("… results truncated at \(maxResults) matching lines")
        }
        return ToolOutcome(text: result.joined(separator: "\n"))
    }

    private func stat(_ arguments: JSONValue) throws -> ToolOutcome {
        let path = try requiredString("path", in: arguments)
        _ = try engine.require(moduleId: moduleId, path: path, operation: .read)
        let url = URL(fileURLWithPath: PathPolicy.normalize(path))
        let report = try FileMetadata.report(path: url.path, url: url)
        audit.write("filesystem", "stat \(url.path)")
        return ToolOutcome(text: report)
    }

    private func readBytes(_ arguments: JSONValue) throws -> ToolOutcome {
        let path = try requiredString("path", in: arguments)
        _ = try engine.require(moduleId: moduleId, path: path, operation: .read)
        let url = URL(fileURLWithPath: PathPolicy.normalize(path))
        let total = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let offset = max(arguments["offset"]?.numberValue.map(Int64.init) ?? 0, 0)
        let requested = arguments["length"]?.numberValue.map(Int.init) ?? 4096
        let length = min(max(requested, 1), 4096)
        let encoding = arguments["encoding"]?.stringValue ?? "both"

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(min(offset, total)))
        let data = (try? handle.read(upToCount: length)) ?? Data()

        var lines: [String] = [
            "path: \(url.path)",
            "total: \(total) bytes",
            "offset: \(offset)",
            "read: \(data.count) bytes",
        ]
        if encoding == "hex" || encoding == "both" {
            lines.append("hex: \(data.map { String(format: "%02x", $0) }.joined())")
        }
        if encoding == "base64" || encoding == "both" {
            lines.append("base64: \(data.base64EncodedString())")
        }
        audit.write("filesystem", "read_bytes \(url.path) offset=\(offset) len=\(data.count)")
        return ToolOutcome(text: lines.joined(separator: "\n"))
    }

    private func edit(_ arguments: JSONValue) throws -> ToolOutcome {
        let path = try requiredString("path", in: arguments)
        _ = try engine.require(moduleId: moduleId, path: path, operation: .edit)
        let url = URL(fileURLWithPath: PathPolicy.normalize(path))
        let data = try Data(contentsOf: url)
        guard data.count <= maximumEditBytes else {
            return ToolOutcome(text: "File is larger than \(maximumEditBytes) bytes; refusing to edit.", isError: true)
        }
        guard var text = String(data: data, encoding: .utf8) else {
            return ToolOutcome(text: "File is not valid UTF-8; refusing to edit.", isError: true)
        }

        let mode = arguments["mode"]?.stringValue ?? "replace"
        switch mode {
        case "patch":
            let patch = try requiredString("patch", in: arguments)
            let result = try UnifiedPatch.apply(patch, to: text)
            text = result.text
            try Data(text.utf8).write(to: url, options: .atomic)
            audit.write("filesystem", "edit patch \(url.path) hunks=\(result.hunks)")
            return ToolOutcome(text: "Applied \(result.hunks) hunk(s) to \(url.path)")
        case "replace":
            let old = try requiredString("old", in: arguments)
            let new = arguments["new"]?.stringValue ?? ""
            let replaceAll = arguments["all"]?.boolValue ?? false
            let occurrences = text.components(separatedBy: old).count - 1
            guard occurrences > 0 else {
                return ToolOutcome(text: "No occurrence of the search text found in \(url.path).", isError: true)
            }
            text = replaceAll
                ? text.replacingOccurrences(of: old, with: new)
                : text.replacingOccurrences(of: old, with: new, options: [], range: text.range(of: old))
            try Data(text.utf8).write(to: url, options: .atomic)
            let replaced = replaceAll ? occurrences : 1
            audit.write("filesystem", "edit replace \(url.path) occurrences=\(replaced)")
            return ToolOutcome(text: "Replaced \(replaced) occurrence(s) in \(url.path)")
        default:
            throw SphereError.protocolError("unknown fs_edit mode '\(mode)' (expected replace or patch)")
        }
    }

    private func select(_ arguments: JSONValue) throws -> ToolOutcome {
        let path = try requiredString("path", in: arguments)
        let selector = try requiredString("selector", in: arguments)
        _ = try engine.require(moduleId: moduleId, path: path, operation: .read)
        let url = URL(fileURLWithPath: PathPolicy.normalize(path))

        if selector.hasPrefix("lines:") {
            let text = try StructuredData.sliceLines(url: url, selector: selector)
            audit.write("filesystem", "select lines \(url.path) \(selector)")
            return ToolOutcome(text: text)
        }

        let hint = arguments["format"]?.stringValue
        let loaded = try StructuredData.load(url: url, formatHint: hint)
        let selected = try StructuredData.select(loaded.value, selector: selector)
        var text = StructuredData.pretty(selected)
        if text.count > 100_000 {
            text = String(text.prefix(100_000)) + "\n… output truncated at 100000 characters"
        }
        audit.write("filesystem", "select \(url.path) '\(selector)' format=\(loaded.format)")
        return ToolOutcome(text: "format: \(loaded.format)\nselector: \(selector)\n\n\(text)")
    }

    private func imageInspect(_ arguments: JSONValue) throws -> ToolOutcome {
        let path = try requiredString("path", in: arguments)
        _ = try engine.require(moduleId: moduleId, path: path, operation: .read)
        let url = URL(fileURLWithPath: PathPolicy.normalize(path))
        let thumbnail = arguments["thumbnail"]?.boolValue ?? false
        let size = min(max(arguments["thumbnail_size"]?.numberValue.map(Int.init) ?? 256, 32), 512)
        let report = ImageInspector.inspect(path: url.path, url: url, thumbnail: thumbnail, thumbnailSize: size)
        audit.write("filesystem", "image_inspect \(url.path)")
        return ToolOutcome(text: report)
    }

    // MARK: - Helpers

    private func requiredString(_ key: String, in arguments: JSONValue) throws -> String {
        guard let value = arguments[key]?.stringValue, !value.isEmpty else {
            throw SphereError.protocolError("missing or empty argument '\(key)'")
        }
        return value
    }

    static func relativePath(_ url: URL, root: URL) -> String {
        let rootComponents = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let fileComponents = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        var index = 0
        while index < rootComponents.count,
              index < fileComponents.count,
              rootComponents[index] == fileComponents[index] {
            index += 1
        }
        return fileComponents.dropFirst(index).joined(separator: "/")
    }

    static func lineSlice(_ text: String, start: Int, end: Int) -> String {
        let lines = text.components(separatedBy: .newlines)
        let from = min(max(start - 1, 0), lines.count)
        let to = min(max(end, from), lines.count)
        guard from < to else { return "" }
        return lines[from..<to].enumerated().map { index, line in
            String(format: "%6d\t%@", from + index + 1, line)
        }.joined(separator: "\n")
    }

    private static func globRegex(_ glob: String) throws -> NSRegularExpression {
        var pattern = "^"
        var index = glob.startIndex
        while index < glob.endIndex {
            let character = glob[index]
            switch character {
            case "*":
                let next = glob.index(after: index)
                if next < glob.endIndex, glob[next] == "*" {
                    pattern += ".*"
                    index = next
                } else {
                    pattern += "[^/]*"
                }
            case "?":
                pattern += "[^/]"
            case ".", "+", "(", ")", "[", "]", "{", "}", "^", "$", "|", "\\":
                pattern += "\\\(character)"
            default:
                pattern += String(character)
            }
            index = glob.index(after: index)
        }
        pattern += "$"
        return try NSRegularExpression(pattern: pattern)
    }
}
