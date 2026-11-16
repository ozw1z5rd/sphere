import Foundation
import SphereCore

/// Read-only git inspection tools: status, diff, log, show and blame.
public final class GitToolProvider: ToolProvider {
    public let moduleId = "sphere.git"
    public let providerName = "Git (read-only)"

    private let engine: PermissionEngine
    private let audit: AuditLog
    private let gitURL = URL(fileURLWithPath: "/usr/bin/git")

    public init(engine: PermissionEngine, audit: AuditLog = AuditLog()) {
        self.engine = engine
        self.audit = audit
    }

    public func definitions() -> [ToolDefinition] {
        [
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "git"),
                originalName: "git",
                moduleId: moduleId,
                description: "Run a read-only git inspection command inside a granted path: status, diff, log, show or blame.",
                inputSchema: ToolSchemas.object(properties: [
                    "operation": ToolSchemas.choice(["status", "diff", "log", "show", "blame"]),
                    "path": ToolSchemas.string("Repository directory (or a file inside it)."),
                    "file": ToolSchemas.string("Optional file path relative to the repository."),
                    "rev": ToolSchemas.string("Revision for show (default HEAD)."),
                    "staged": ToolSchemas.boolean("For diff: show staged changes."),
                    "stat": ToolSchemas.boolean("For diff: show a diffstat."),
                    "count": ToolSchemas.integer("For log: number of commits (default 20, max 100)."),
                ], required: ["operation", "path"])
            ),
        ]
    }

    public func invoke(tool: String, arguments: JSONValue, sessionId: String?) async throws -> ToolOutcome {
        guard tool == "git" else {
            throw SphereError.protocolError("unknown git tool '\(tool)'")
        }
        guard let operation = arguments["operation"]?.stringValue else {
            throw SphereError.protocolError("missing argument 'operation'")
        }
        let rawPath = try requiredString("path", in: arguments)
        let cwd = try workingDirectory(rawPath)
        _ = try engine.require(moduleId: moduleId, sessionId: sessionId, path: cwd.path, operation: .read)

        var gitArguments = ["-C", cwd.path, "--no-pager"]
        switch operation {
        case "status":
            gitArguments += ["status", "--short", "--branch"]
        case "diff":
            gitArguments += ["diff", "--no-color"]
            if arguments["staged"]?.boolValue == true { gitArguments.append("--staged") }
            if arguments["stat"]?.boolValue == true { gitArguments.append("--stat") }
            if let file = arguments["file"]?.stringValue, !file.isEmpty {
                _ = try engine.require(moduleId: moduleId, sessionId: sessionId, path: inGrant(file, cwd: cwd).path, operation: .read)
                gitArguments += ["--", file]
            }
        case "log":
            let count = min(max(arguments["count"]?.numberValue.map(Int.init) ?? 20, 1), 100)
            gitArguments += ["log", "--oneline", "--decorate", "-n", String(count)]
        case "show":
            let rev = arguments["rev"]?.stringValue ?? "HEAD"
            guard rev.range(of: "^[A-Za-z0-9._~^@{}\\\\/-]+$", options: .regularExpression) != nil,
                  !rev.hasPrefix("-") else {
                throw SphereError.protocolError("invalid revision '\(rev)'")
            }
            gitArguments += ["show", "--stat", "--no-color", rev]
            if let file = arguments["file"]?.stringValue, !file.isEmpty {
                _ = try engine.require(moduleId: moduleId, sessionId: sessionId, path: inGrant(file, cwd: cwd).path, operation: .read)
                gitArguments += ["--", file]
            }
        case "blame":
            guard let file = arguments["file"]?.stringValue, !file.isEmpty else {
                throw SphereError.protocolError("blame requires 'file'")
            }
            _ = try engine.require(moduleId: moduleId, sessionId: sessionId, path: inGrant(file, cwd: cwd).path, operation: .read)
            gitArguments += ["blame", "--date=iso", "--", file]
        default:
            throw SphereError.protocolError("unsupported git operation '\(operation)' (read-only status/diff/log/show/blame)")
        }

        let environment = ProcessRunner.sanitizedEnvironment(extra: [
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_OPTIONAL_LOCKS": "0",
            "GIT_PAGER": "cat",
            "PAGER": "cat",
        ])
        let profile = ExecToolProvider.sandboxProfile(grantedRoot: cwd, allowWrites: false)
        let result = try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
            arguments: ["-p", profile, "--", gitURL.path] + gitArguments,
            cwd: cwd,
            environment: environment,
            timeout: 20,
            maxOutputBytes: 100_000
        )
        audit.write("git", "\(operation) in \(cwd.path) exit=\(result.exitCode)")

        var sections: [String] = ["git \(operation) in \(cwd.path)"]
        if !result.stdout.isEmpty { sections.append(result.stdout.trimmingCharacters(in: .newlines)) }
        if !result.stderr.isEmpty { sections.append("stderr:\n" + result.stderr.trimmingCharacters(in: .newlines)) }
        if result.timedOut { sections.append("… timed out after 20s") }
        return ToolOutcome(
            text: sections.joined(separator: "\n\n"),
            isError: result.exitCode != 0 || result.timedOut
        )
    }

    private func workingDirectory(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: PathPolicy.normalize(path))
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw SphereError.protocolError("path does not exist: \(url.path)")
        }
        return isDirectory.boolValue ? url : url.deletingLastPathComponent()
    }

    private func inGrant(_ file: String, cwd: URL) -> URL {
        if file.hasPrefix("/") {
            return URL(fileURLWithPath: PathPolicy.normalize(file))
        }
        return cwd.appendingPathComponent(file).standardizedFileURL
    }

    private func requiredString(_ key: String, in arguments: JSONValue) throws -> String {
        guard let value = arguments[key]?.stringValue, !value.isEmpty else {
            throw SphereError.protocolError("missing or empty argument '\(key)'")
        }
        return value
    }
}
