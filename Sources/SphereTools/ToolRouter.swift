import Foundation
import SphereCore
import SphereMCP

/// Aggregates built-in providers and MCP modules into one tool catalog and
/// dispatches invocations, enforcing the per-tool policy.
public actor ToolRouter {
    private let host: MCPModuleHost
    private let providers: [ToolProvider]
    private var policy: [String: String]
    private var disabledTools: Set<String>

    /// Called for tools whose policy is `ask`. Return `true` to allow.
    public var approvalHandler: (@Sendable (ToolDefinition) async -> Bool)?

    public init(
        host: MCPModuleHost,
        providers: [ToolProvider],
        policy: [String: String] = [:],
        disabledTools: [String] = []
    ) {
        self.host = host
        self.providers = providers
        self.policy = policy
        self.disabledTools = Set(disabledTools)
    }

    public func setPolicy(_ policy: [String: String]) {
        self.policy = policy
    }

    public func setDisabledTools(_ names: [String]) {
        disabledTools = Set(names)
    }

    public func definitions(includingDisabled: Bool = false) async -> [ToolDefinition] {
        var result = providers.flatMap { $0.definitions() }
        let catalog = await host.catalog()
        for (moduleId, tools) in catalog {
            for tool in tools {
                result.append(
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
        if !includingDisabled {
            result = result.filter { !disabledTools.contains($0.name) }
        }
        return result.sorted { $0.name < $1.name }
    }

    public func definition(named name: String) async -> ToolDefinition? {
        await definitions().first(where: { $0.name == name })
    }

    public func invoke(name: String, arguments: JSONValue) async throws -> ToolOutcome {
        guard !disabledTools.contains(name) else {
            throw SphereError.permissionDenied("tool '\(name)' is disabled")
        }
        let all = await definitions()
        guard let definition = all.first(where: { $0.name == name }) else {
            throw SphereError.protocolError("unknown tool '\(name)'")
        }

        if let effect = policy[name] {
            if effect == "deny" {
                throw SphereError.permissionDenied("tool '\(name)' is denied by policy")
            }
            if effect == "ask" {
                guard let approvalHandler, await approvalHandler(definition) else {
                    throw SphereError.permissionDenied("tool '\(name)' requires approval and no approval handler is available")
                }
            }
        }

        if let provider = providers.first(where: { $0.moduleId == definition.moduleId }) {
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
