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

    public init(engine: PermissionEngine, audit: AuditLog = AuditLog(), maximumReadBytes: Int = 2_000_000) {
        self.engine = engine
        self.audit = audit
        self.maximumReadBytes = maximumReadBytes
    }

    public func definitions() -> [ToolDefinition] {
        [
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "fs_read"),
                originalName: "fs_read",
                moduleId: moduleId,
                description: "Read a UTF-8 text file from a path granted to Sphere.",
                inputSchema: Self.schema(properties: ["path": ["type": "string"]], required: ["path"])
            ),
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "fs_write"),
                originalName: "fs_write",
                moduleId: moduleId,
                description: "Write UTF-8 text to a path granted in read-write mode.",
                inputSchema: Self.schema(
                    properties: ["path": ["type": "string"], "content": ["type": "string"]],
                    required: ["path", "content"]
                )
            ),
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "fs_list"),
                originalName: "fs_list",
                moduleId: moduleId,
                description: "List the entries of a granted directory.",
                inputSchema: Self.schema(properties: ["path": ["type": "string"]], required: ["path"])
            ),
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "fs_glob"),
                originalName: "fs_glob",
                moduleId: moduleId,
                description: "Find files under a granted directory matching a glob pattern (supports *, ?, **).",
                inputSchema: Self.schema(
                    properties: ["path": ["type": "string"], "pattern": ["type": "string"]],
                    required: ["path", "pattern"]
                )
            ),
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "fs_grep"),
                originalName: "fs_grep",
                moduleId: moduleId,
                description: "Search text files under a granted directory for a regular expression.",
                inputSchema: Self.schema(
                    properties: [
                        "path": ["type": "string"],
                        "pattern": ["type": "string"],
                        "include": ["type": "string"],
                    ],
                    required: ["path", "pattern"]
                )
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
        default: throw SphereError.protocolError("unknown filesystem tool '\(tool)'")
        }
    }

    // MARK: - Operations

    private func read(_ arguments: JSONValue) throws -> ToolOutcome {
        let path = try requiredString("path", in: arguments)
        _ = try engine.require(moduleId: moduleId, path: path, operation: .read)
        let data = try Data(contentsOf: URL(fileURLWithPath: PathPolicy.normalize(path)))
        guard data.count <= maximumReadBytes else {
            return ToolOutcome(
                text: "File is larger than \(maximumReadBytes) bytes; refusing to read.",
                isError: true
            )
        }
        let text = String(data: data, encoding: .utf8) ?? "<binary file: \(data.count) bytes>"
        audit.write("filesystem", "read \(PathPolicy.normalize(path)) (\(data.count) bytes)")
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
                let relative = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
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
        let grant = try engine.require(moduleId: moduleId, path: path, operation: .grep)
        let root = URL(fileURLWithPath: PathPolicy.normalize(path))
        let regex = try NSRegularExpression(pattern: pattern)
        let includeRegex = try include.map(Self.globRegex)
        var results: [String] = []

        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if results.count >= 500 { break }
                let relative = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
                if let includeRegex,
                   includeRegex.firstMatch(in: relative, range: NSRange(relative.startIndex..., in: relative)) == nil {
                    continue
                }
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size > 0, size < maximumReadBytes, let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    continue
                }
                for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                    if regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                        results.append("\(relative):\(index + 1): \(line)")
                        if results.count >= 500 { break }
                    }
                }
            }
        }
        audit.write("filesystem", "grep \(root.path) '\(pattern)' -> \(results.count) matches (grant \(grant.id))")
        return ToolOutcome(text: results.joined(separator: "\n"))
    }

    // MARK: - Helpers

    private func requiredString(_ key: String, in arguments: JSONValue) throws -> String {
        guard let value = arguments[key]?.stringValue, !value.isEmpty else {
            throw SphereError.protocolError("missing or empty argument '\(key)'")
        }
        return value
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

    private static func schema(properties: [String: [String: String]], required: [String]) -> JSONValue {
        var propertyValues: [String: JSONValue] = [:]
        for (key, value) in properties {
            propertyValues[key] = .object(value.mapValues { JSONValue.string($0) })
        }
        return .object([
            "type": .string("object"),
            "properties": .object(propertyValues),
            "required": .array(required.map { JSONValue.string($0) }),
        ])
    }
}
