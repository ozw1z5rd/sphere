import Foundation
import SphereCore

/// Owns one `MCPClient` per running module and caches the tool catalog.
public actor MCPModuleHost {
    private var clients: [String: MCPClient] = [:]
    private var tools: [String: [MCPTool]] = [:]
    private var logs: [String: [String]] = [:]

    public init() {}

    public func start(module: InstalledModule) async throws -> [MCPTool] {
        if let existing = tools[module.id], clients[module.id] != nil {
            return existing
        }
        guard let transportConfig = module.manifest.resolvedTransport(installPath: module.installPath) else {
            throw SphereError.invalidManifest("module '\(module.id)' has no transport")
        }
        let workingDirectory = transportConfig.cwd.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let transport = StdioMCPTransport(
            command: transportConfig.command,
            workingDirectory: workingDirectory,
            environment: transportConfig.env
        )
        transport.onLog = { [weak self] text in
            guard let self else { return }
            Task { await self.appendLog(moduleId: module.id, text: text) }
        }

        let client = MCPClient(moduleId: module.id, transport: transport)
        let timeout = TimeInterval((transportConfig.healthCheck?.timeoutMs ?? 20_000)) / 1000.0
        _ = try await client.start(timeout: timeout)
        let catalog = try await client.listTools(timeout: timeout)
        clients[module.id] = client
        tools[module.id] = catalog
        return catalog
    }

    public func stop(moduleId: String) async {
        if let client = clients.removeValue(forKey: moduleId) {
            client.stop()
        }
        tools[moduleId] = nil
    }

    public func stopAll() async {
        for (_, client) in clients {
            client.stop()
        }
        clients.removeAll()
        tools.removeAll()
    }

    public func restart(module: InstalledModule) async throws -> [MCPTool] {
        await stop(moduleId: module.id)
        return try await start(module: module)
    }

    public func catalog() -> [String: [MCPTool]] {
        tools
    }

    public func callTool(moduleId: String, tool: String, arguments: JSONValue, timeout: TimeInterval = 600) async throws -> ToolInvocationResult {
        guard let client = clients[moduleId] else {
            throw SphereError.moduleNotFound(moduleId)
        }
        return try await client.callTool(name: tool, arguments: arguments, timeout: timeout)
    }

    public func moduleLogs(moduleId: String) -> [String] {
        logs[moduleId] ?? []
    }

    private func appendLog(moduleId: String, text: String) {
        var current = logs[moduleId] ?? []
        current.append(text)
        if current.count > 500 {
            current.removeFirst(current.count - 500)
        }
        logs[moduleId] = current
    }
}
