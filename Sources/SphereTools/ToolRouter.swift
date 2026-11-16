import Foundation
import SphereCore
import SphereMCP

/// Aggregates built-in providers and MCP modules into one tool catalog and
/// dispatches invocations, enforcing the per-tool policy.
public actor ToolRouter {
    private let host: MCPModuleHost
    private let providers: [ToolProvider]
    private let audit: AuditLog?
    private var policy: [String: String]
    private var disabledTools: Set<String>
    private var reportedCollisions: Set<String> = []

    /// Called for tools whose policy is `ask`. Return `true` to allow.
    public var approvalHandler: (@Sendable (ToolDefinition) async -> Bool)?

    public init(
        host: MCPModuleHost,
        providers: [ToolProvider],
        policy: [String: String] = [:],
        disabledTools: [String] = [],
        audit: AuditLog? = nil
    ) {
        self.host = host
        self.providers = providers
        self.policy = policy
        self.disabledTools = Set(disabledTools)
        self.audit = audit
    }

    public func setPolicy(_ policy: [String: String]) {
        self.policy = policy
    }

    public func setDisabledTools(_ names: [String]) {
        disabledTools = Set(names)
    }

    public func definitions(includingDisabled: Bool = false) async -> [ToolDefinition] {
        var collected: [ToolDefinition] = []
        var owners: [String: String] = [:]

        func append(_ definition: ToolDefinition) {
            if let kept = owners[definition.name] {
                recordCollision(name: definition.name, kept: kept, ignored: definition.moduleId)
                return
            }
            owners[definition.name] = definition.moduleId
            collected.append(definition)
        }

        for provider in providers {
            for definition in provider.definitions() {
                append(definition)
            }
        }

        let catalog = await host.catalog()
        for moduleId in catalog.keys.sorted() {
            for tool in catalog[moduleId] ?? [] {
                append(
                    ToolDefinition(
                        name: ToolDefinition.namespaced(moduleId: moduleId, toolName: tool.name),
                        originalName: tool.name,
                        moduleId: moduleId,
                        description: tool.description ?? tool.title ?? tool.name,
                        inputSchema: tool.inputSchema
                    )
                )
            }
        }

        // A tool denied by policy (or asking without an approval handler) must
        // not be advertised: the model would call it and waste a step.
        collected = collected.filter { definition in
            let effect = policy[definition.name]
            if effect == "deny" { return false }
            if effect == "ask" && approvalHandler == nil { return false }
            if !includingDisabled && disabledTools.contains(definition.name) { return false }
            return true
        }
        return collected.sorted { $0.name < $1.name }
    }

    private func recordCollision(name: String, kept: String, ignored: String) {
        let key = "\(name)|\(kept)|\(ignored)"
        guard !reportedCollisions.contains(key) else { return }
        reportedCollisions.insert(key)
        audit?.write("router", "tool name collision '\(name)': keeping \(kept), ignoring \(ignored)")
    }

    public func definition(named name: String) async -> ToolDefinition? {
        await definitions().first(where: { $0.name == name })
    }

    public func invoke(name: String, arguments: JSONValue) async throws -> ToolOutcome {
        guard !disabledTools.contains(name) else {
            throw SphereError.permissionDenied("tool '\(name)' is disabled")
        }
        if policy[name] == "deny" {
            throw SphereError.permissionDenied("tool '\(name)' is denied by policy")
        }
        if policy[name] == "ask", approvalHandler == nil {
            throw SphereError.permissionDenied("tool '\(name)' requires approval and no approval handler is available")
        }

        let all = await definitions()
        guard let definition = all.first(where: { $0.name == name }) else {
            throw SphereError.protocolError("unknown tool '\(name)'")
        }

        if policy[name] == "ask", let approvalHandler {
            guard await approvalHandler(definition) else {
                throw SphereError.permissionDenied("tool '\(name)' was not approved")
            }
        }

        // Match by tool ownership, not only by moduleId: an MCP module could
        // reuse a built-in module id, and matching by id would misroute it.
        if let provider = providers.first(where: { provider in
            provider.definitions().contains { $0.name == definition.name }
        }) {
            return try await provider.invoke(tool: definition.originalName, arguments: arguments)
        }

        let result = try await host.callTool(
            moduleId: definition.moduleId,
            tool: definition.originalName,
            arguments: arguments
        )
        let text = result.content.compactMap { content -> String? in
            if let text = content.text { return text }
            if let data = content.data { return data }
            return nil
        }.joined(separator: "\n")
        return ToolOutcome(text: text, isError: result.isError, raw: result.raw)
    }
}
