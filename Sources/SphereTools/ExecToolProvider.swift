import Foundation
import SphereCore

/// Sandboxed command execution. Commands are passed as an argv array (never a
/// shell), must match an allowlist, run inside a granted directory, are wrapped
/// in a sandbox profile that denies network access and writes outside the
/// granted root, and have a hard timeout.
public final class ExecToolProvider: ToolProvider {
    public let moduleId = "sphere.exec"
    public let providerName = "Sandboxed Exec"

    public static let defaultAllowlist: [String] = [
        "git status", "git diff", "git log", "git show", "git blame",
        "git rev-parse", "git ls-files", "git grep",
        "ls", "cat", "head", "tail", "wc", "file", "stat", "diff", "sort", "uniq",
        "rg", "grep", "find", "jq",
        "swift build", "swift test", "swift package",
        "make", "npm test", "npm run", "pnpm test", "pnpm run",
        "cargo test", "cargo build", "go test", "go build",
    ]

    private static let readOnlyPrefixes: [String] = [
        "git status", "git diff", "git log", "git show", "git blame",
        "git rev-parse", "git ls-files", "git grep",
        "ls", "cat", "head", "tail", "wc", "file", "stat", "diff", "sort", "uniq",
        "rg", "grep", "find", "jq",
    ]

    private let engine: PermissionEngine
    private let audit: AuditLog
    private let lock = NSLock()
    private var enabled: Bool
    private var allowlist: [String]

    public init(
        engine: PermissionEngine,
        audit: AuditLog = AuditLog(),
        enabled: Bool = false,
        allowlist: [String] = ExecToolProvider.defaultAllowlist
    ) {
        self.engine = engine
        self.audit = audit
        self.enabled = enabled
        self.allowlist = allowlist
    }

    public func update(enabled: Bool, allowlist: [String]) {
        lock.lock()
        self.enabled = enabled
        self.allowlist = allowlist
        lock.unlock()
    }

    private func policySnapshot() -> (Bool, [String]) {
        lock.lock()
        defer { lock.unlock() }
        return (enabled, allowlist)
    }

    public func definitions() -> [ToolDefinition] {
        [
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "exec"),
                originalName: "exec",
                moduleId: moduleId,
                description: "Run an allowlisted command inside a granted directory. argv array only (no shell), hard timeout, no network, writes restricted to the granted root. Disabled until enabled in Settings → Tools.",
                inputSchema: ToolSchemas.object(properties: [
                    "argv": ToolSchemas.stringArray("Command and arguments, e.g. [\"git\", \"status\"]."),
                    "cwd": ToolSchemas.string("Working directory; must be inside a granted root."),
                    "timeout_ms": ToolSchemas.integer("Timeout in milliseconds (default 30000, max 120000)."),
                    "max_output_bytes": ToolSchemas.integer("Maximum output bytes (default 200000)."),
                ], required: ["argv", "cwd"])
            ),
        ]
    }

    public func invoke(tool: String, arguments: JSONValue, sessionId: String?) async throws -> ToolOutcome {
        guard tool == "exec" else {
            throw SphereError.protocolError("unknown exec tool '\(tool)'")
        }

        let (isEnabled, allowed) = policySnapshot()
        guard isEnabled else {
            throw SphereError.notConfigured("exec is disabled; enable it in Settings → Tools")
        }

        guard let values = arguments["argv"]?.arrayValue else {
            throw SphereError.protocolError("missing argument 'argv'")
        }
        let argv = values.compactMap(\.stringValue)
        guard !argv.isEmpty, !argv[0].isEmpty else {
            throw SphereError.protocolError("argv must contain at least the executable")
        }
        guard Self.isAllowed(argv: argv, allowlist: allowed) else {
            throw SphereError.permissionDenied(
                "'\(argv.prefix(2).joined(separator: " "))' is not in the exec allowlist"
            )
        }
        guard let executable = Self.resolveExecutable(argv[0]) else {
            throw SphereError.protocolError("executable '\(argv[0])' not found in the system paths")
        }

        let cwdPath = try requiredString("cwd", in: arguments)
        let cwd = URL(fileURLWithPath: PathPolicy.normalize(cwdPath))
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SphereError.protocolError("cwd is not a directory: \(cwd.path)")
        }
        let needsWrite = !Self.isReadOnly(argv: argv)
        _ = try engine.require(moduleId: moduleId, sessionId: sessionId, path: cwd.path, operation: needsWrite ? .edit : .read)

        let timeout = min(max(arguments["timeout_ms"]?.numberValue.map(Int.init) ?? 30_000, 1_000), 120_000)
        let maxOutput = min(max(arguments["max_output_bytes"]?.numberValue.map(Int.init) ?? 200_000, 4_096), 500_000)
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("sphere-exec-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: home.appendingPathComponent("tmp"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let profile = Self.sandboxProfile(grantedRoot: cwd, allowWrites: needsWrite)
        let launchArguments = ["-p", profile, "--", executable.path] + Array(argv.dropFirst())
        let environment = ProcessRunner.sanitizedEnvironment(home: home, extra: [
            "GIT_OPTIONAL_LOCKS": "0",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_PAGER": "cat",
            "PAGER": "cat",
        ])

        let result = try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
            arguments: launchArguments,
            cwd: cwd,
            environment: environment,
            timeout: TimeInterval(timeout) / 1000.0,
            maxOutputBytes: maxOutput
        )
        audit.write(
            "exec",
            "\(argv.prefix(4).joined(separator: " ")) in \(cwd.path) exit=\(result.exitCode) timeout=\(result.timedOut)"
        )

        var sections: [String] = [
            "$ \(argv.joined(separator: " "))",
            "cwd: \(cwd.path)",
            "exit: \(result.exitCode)" + (result.timedOut ? " (timed out)" : ""),
        ]
        if !result.stdout.isEmpty { sections.append(result.stdout.trimmingCharacters(in: .newlines)) }
        if !result.stderr.isEmpty { sections.append("stderr:\n" + result.stderr.trimmingCharacters(in: .newlines)) }
        if result.truncated { sections.append("… output truncated") }
        return ToolOutcome(
            text: sections.joined(separator: "\n\n"),
            isError: result.exitCode != 0 || result.timedOut
        )
    }

    // MARK: - Policy helpers (also used by tests)

    static func isAllowed(argv: [String], allowlist: [String]) -> Bool {
        for entry in allowlist {
            let tokens = entry.split(separator: " ").map(String.init)
            guard !tokens.isEmpty, argv.count >= tokens.count else { continue }
            if Array(argv.prefix(tokens.count)) == tokens { return true }
        }
        return false
    }

    static func isReadOnly(argv: [String]) -> Bool {
        for prefix in readOnlyPrefixes {
            let tokens = prefix.split(separator: " ").map(String.init)
            guard argv.count >= tokens.count else { continue }
            if Array(argv.prefix(tokens.count)) == tokens { return true }
        }
        return false
    }

    static func resolveExecutable(_ name: String) -> URL? {
        if name.contains("/") {
            let url = URL(fileURLWithPath: name)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        let paths = ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/usr/local/bin", "/opt/homebrew/bin"]
        for directory in paths {
            let candidate = directory + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    static func sandboxProfile(grantedRoot: URL, allowWrites: Bool) -> String {
        func quote(_ value: String) -> String {
            value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let home = quote(FileManager.default.homeDirectoryForCurrentUser.path)
        var profile = """
        (version 1)
        (allow default)
        (deny network*)
        (deny file-read* (subpath "\(home)/.ssh") (subpath "\(home)/.aws") (subpath "\(home)/.gnupg") (subpath "\(home)/.docker") (subpath "\(home)/Library/Application Support/Sphere") (literal "\(home)/.netrc"))
        (deny file-write*)
        (allow file-write* (subpath "\(quote(grantedRoot.path))") (subpath "/private/tmp") (subpath "/private/var/folders") (literal "/dev/null") (literal "/dev/stdout") (literal "/dev/stderr") (literal "/dev/zero"))
        """
        if !allowWrites {
            // Reads are fine, but a read-only grant must not become writable
            // through a child process.
            profile = profile.replacingOccurrences(
                of: "(subpath \"\(quote(grantedRoot.path))\") ",
                with: ""
            )
        }
        return profile
    }

    private func requiredString(_ key: String, in arguments: JSONValue) throws -> String {
        guard let value = arguments[key]?.stringValue, !value.isEmpty else {
            throw SphereError.protocolError("missing or empty argument '\(key)'")
        }
        return value
    }
}
