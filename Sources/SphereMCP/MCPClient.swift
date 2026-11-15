import Foundation
import SphereCore

/// MCP client over an abstract transport. Handles the `initialize` handshake,
/// request/response correlation, timeouts and tool calls.
public final class MCPClient: @unchecked Sendable {
    private struct Pending {
        let method: String
        let continuation: CheckedContinuation<JSONValue, Error>
        let watchdog: Task<Void, Never>
    }

    private final class RequestStore: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [Int: Pending] = [:]

        func add(_ id: Int, _ entry: Pending) {
            lock.lock()
            entries[id] = entry
            lock.unlock()
        }

        func remove(_ id: Int) -> Pending? {
            lock.lock()
            defer { lock.unlock() }
            return entries.removeValue(forKey: id)
        }

        func drain() -> [Pending] {
            lock.lock()
            defer { lock.unlock() }
            let all = Array(entries.values)
            entries.removeAll()
            return all
        }
    }

    public let moduleId: String
    private let transport: MCPTransport
    private let store = RequestStore()
    private let idLock = NSLock()
    private var nextID = 1
    private var readerTask: Task<Void, Never>?
    private var started = false
    public private(set) var serverInfo = MCPServerInfo()

    public init(moduleId: String, transport: MCPTransport) {
        self.moduleId = moduleId
        self.transport = transport
    }

    @discardableResult
    public func start(timeout: TimeInterval = 20) async throws -> MCPServerInfo {
        guard !started else { return serverInfo }
        try transport.start()
        started = true
        startReader()

        do {
            let params = JSONValue.object([
                "protocolVersion": .string("2025-06-18"),
                "capabilities": .object([:]),
                "clientInfo": .object([
                    "name": .string("Sphere"),
                    "version": .string("0.1.0"),
                ]),
            ])
            let result = try await request(method: "initialize", params: params, timeout: timeout)
            try sendNotification(method: "notifications/initialized")

            serverInfo = MCPServerInfo(
                name: result["serverInfo"]?["name"]?.stringValue,
                version: result["serverInfo"]?["version"]?.stringValue,
                protocolVersion: result["protocolVersion"]?.stringValue,
                instructions: result["instructions"]?.stringValue
            )
            return serverInfo
        } catch {
            stop()
            throw error
        }
    }

    public func listTools(timeout: TimeInterval = 15) async throws -> [MCPTool] {
        let result = try await request(method: "tools/list", params: .object([:]), timeout: timeout)
        guard let tools = result["tools"]?.arrayValue else { return [] }
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        return tools.compactMap { value in
            guard let data = try? encoder.encode(value) else { return nil }
            return try? decoder.decode(MCPTool.self, from: data)
        }
    }

    public func callTool(
        name: String,
        arguments: JSONValue = .object([:]),
        timeout: TimeInterval = 600
    ) async throws -> ToolInvocationResult {
        let params = JSONValue.object([
            "name": .string(name),
            "arguments": arguments,
        ])
        let result = try await request(method: "tools/call", params: params, timeout: timeout)
        return ToolInvocationResult(
            content: Self.parseContent(result["content"]),
            isError: result["isError"]?.boolValue ?? false,
            raw: result
        )
    }

    public func stop() {
        readerTask?.cancel()
        readerTask = nil
        transport.stop()
        failAll(with: SphereError.transportUnavailable)
        started = false
    }

    // MARK: - Internals

    private func startReader() {
        let incoming = transport.incoming
        readerTask = Task { [weak self] in
            do {
                for try await line in incoming {
                    self?.handle(line: line)
                }
            } catch {
                self?.failAll(with: SphereError.protocolError("transport closed: \(error.localizedDescription)"))
            }
        }
    }

    private func handle(line: Data) {
        guard let message = try? JSONDecoder().decode(JSONRPCMessage.self, from: line) else {
            return
        }
        guard let id = message.id, let entry = store.remove(id) else {
            return
        }
        entry.watchdog.cancel()
        if let error = message.error {
            entry.continuation.resume(throwing: error)
        } else {
            entry.continuation.resume(returning: message.result ?? .null)
        }
    }

    private func request(method: String, params: JSONValue?, timeout: TimeInterval) async throws -> JSONValue {
        let id: Int = {
            idLock.lock()
            defer { idLock.unlock() }
            let value = nextID
            nextID += 1
            return value
        }()

        let message = JSONRPCMessage.request(id: id, method: method, params: params)
        let data = try JSONEncoder().encode(message)

        return try await withCheckedThrowingContinuation { continuation in
            let watchdog = Task { [weak self] in
                let nanoseconds = UInt64(max(timeout, 0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                self?.expire(id: id)
            }
            store.add(id, Pending(method: method, continuation: continuation, watchdog: watchdog))
            do {
                try transport.send(data)
            } catch {
                if let entry = store.remove(id) {
                    entry.watchdog.cancel()
                    entry.continuation.resume(throwing: error)
                }
            }
        }
    }

    private func sendNotification(method: String, params: JSONValue? = nil) throws {
        let message = JSONRPCMessage.notification(method: method, params: params)
        try transport.send(JSONEncoder().encode(message))
    }

    private func expire(id: Int) {
        guard let entry = store.remove(id) else { return }
        entry.continuation.resume(throwing: SphereError.timeout(entry.method))
    }

    private func failAll(with error: Error) {
        for entry in store.drain() {
            entry.watchdog.cancel()
            entry.continuation.resume(throwing: error)
        }
    }

    private static func parseContent(_ value: JSONValue?) -> [ToolContent] {
        guard let items = value?.arrayValue else { return [] }
        return items.compactMap { item in
            guard let type = item["type"]?.stringValue else { return nil }
            return ToolContent(
                type: type,
                text: item["text"]?.stringValue,
                data: item["data"]?.stringValue,
                mimeType: item["mimeType"]?.stringValue
            )
        }
    }
}
