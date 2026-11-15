import Foundation
import AppKit
import SphereCore

/// Local context and clipboard access: date, OS, host and granted roots, plus
/// read/write of the system pasteboard.
public final class SystemToolProvider: ToolProvider {
    public let moduleId = "sphere.system"
    public let providerName = "System"

    private let permissions: PermissionStore
    private let audit: AuditLog

    public init(permissions: PermissionStore, audit: AuditLog = AuditLog()) {
        self.permissions = permissions
        self.audit = audit
    }

    public func definitions() -> [ToolDefinition] {
        [
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "system_info"),
                originalName: "system_info",
                moduleId: moduleId,
                description: "Return current date/time, OS version, architecture, hostname, user and the granted working roots.",
                inputSchema: ToolSchemas.object(properties: [:])
            ),
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "clipboard_read"),
                originalName: "clipboard_read",
                moduleId: moduleId,
                description: "Read the system clipboard as text (and list its types when it has no text).",
                inputSchema: ToolSchemas.object(properties: [
                    "max_chars": ToolSchemas.integer("Maximum characters to return (default 20000)."),
                ])
            ),
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "clipboard_write"),
                originalName: "clipboard_write",
                moduleId: moduleId,
                description: "Replace the system clipboard with the given text.",
                inputSchema: ToolSchemas.object(properties: [
                    "text": ToolSchemas.string(),
                ], required: ["text"])
            ),
        ]
    }

    public func invoke(tool: String, arguments: JSONValue) async throws -> ToolOutcome {
        switch tool {
        case "system_info": return try info()
        case "clipboard_read": return try clipboardRead(arguments)
        case "clipboard_write": return try clipboardWrite(arguments)
        default: throw SphereError.protocolError("unknown system tool '\(tool)'")
        }
    }

    private func info() throws -> ToolOutcome {
        let now = Date()
        let process = ProcessInfo.processInfo
        let grants = (try? permissions.pathGrants()) ?? []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines: [String] = [
            "date: \(formatter.string(from: now))",
            "timezone: \(TimeZone.current.identifier)",
            "os: \(process.operatingSystemVersionString)",
            "architecture: \(Self.architecture)",
            "hostname: \(process.hostName)",
            "user: \(NSUserName())",
            "language: \(Locale.current.identifier)",
            "shell: \(process.environment["SHELL"] ?? "-")",
            "",
            "granted roots:",
        ]
        if grants.isEmpty {
            lines.append("  (none)")
        } else {
            for grant in grants {
                let mode = grant.mode == .readWrite ? "RW" : "RO"
                let recursive = grant.recursive ? "recursive" : "single"
                lines.append("  [\(mode)] \(grant.path) (\(recursive))")
            }
        }
        audit.write("system", "system_info")
        return ToolOutcome(text: lines.joined(separator: "\n"))
    }

    private func clipboardRead(_ arguments: JSONValue) throws -> ToolOutcome {
        let maxChars = min(max(arguments["max_chars"]?.numberValue.map(Int.init) ?? 20_000, 1), 100_000)
        let pasteboard = NSPasteboard.general
        let types = (pasteboard.types ?? []).map(\.rawValue)
        var lines: [String] = ["types: \(types.joined(separator: ", "))"]
        if let text = pasteboard.string(forType: .string) {
            let value = text.count > maxChars ? String(text.prefix(maxChars)) + "\n… truncated" : text
            lines.append("text (\(text.count) chars):\n\(value)")
        } else if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            lines.append("urls:\n" + urls.map(\.absoluteString).joined(separator: "\n"))
        } else {
            lines.append("No text or file URLs on the clipboard.")
        }
        audit.write("system", "clipboard_read")
        return ToolOutcome(text: lines.joined(separator: "\n"))
    }

    private func clipboardWrite(_ arguments: JSONValue) throws -> ToolOutcome {
        guard let text = arguments["text"]?.stringValue else {
            throw SphereError.protocolError("missing argument 'text'")
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            return ToolOutcome(text: "Could not write to the clipboard.", isError: true)
        }
        audit.write("system", "clipboard_write \(text.utf8.count) bytes")
        return ToolOutcome(text: "Wrote \(text.count) characters to the clipboard.")
    }

    private static var architecture: String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}
