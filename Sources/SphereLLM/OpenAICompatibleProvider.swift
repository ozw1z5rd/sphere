import Foundation
import SphereCore

/// Works with OpenAI, Ollama, LM Studio, OpenRouter, DeepSeek and any other
/// OpenAI-compatible chat completions endpoint.
public final class OpenAICompatibleProvider: LLMProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String

    private let config: ProviderConfig
    private let apiKey: String?
    private let debugLogging: Bool
    private let session: URLSession

    private struct ToolAccumulator {
        var id: String?
        var name: String = ""
        var arguments: String = ""
    }

    public init(
        config: ProviderConfig,
        apiKey: String?,
        debugLogging: Bool = false,
        session: URLSession = .shared
    ) {
        self.id = config.id
        self.displayName = config.name
        self.config = config
        self.apiKey = apiKey
        self.debugLogging = debugLogging
        self.session = session
    }

    public func stream(request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request: request, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func listModels() async throws -> [LLMModel] {
        let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
        guard let url = URL(string: base + "/models") else {
            throw SphereError.notConfigured("invalid provider base URL '\(config.baseURL)'")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        if let apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        NetworkLog.logRequest(provider: displayName, request: urlRequest, body: nil, full: debugLogging)
        logMissingKey()

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw SphereError.protocolError("missing HTTP response")
        }
        let payload = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(http.statusCode) else {
            NetworkLog.logResponse(
                provider: displayName,
                url: url.absoluteString,
                status: http.statusCode,
                body: payload,
                full: true,
                isSuccess: false
            )
            throw SphereError.protocolError("HTTP \(http.statusCode) from \(displayName): \(payload)")
        }
        NetworkLog.logResponse(
            provider: displayName,
            url: url.absoluteString,
            status: http.statusCode,
            body: debugLogging ? payload : "",
            full: debugLogging,
            isSuccess: true
        )
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = json["data"] as? [[String: Any]]
        else {
            return []
        }
        return items.compactMap { item -> LLMModel? in
            guard let id = item["id"] as? String else { return nil }
            let created = (item["created"] as? Double).map(Date.init(timeIntervalSince1970:))
            return LLMModel(id: id, ownedBy: item["owned_by"] as? String, created: created)
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    private func run(request: LLMRequest, continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation) async throws {
        let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
        guard let url = URL(string: base + "/chat/completions") else {
            throw SphereError.notConfigured("invalid provider base URL '\(config.baseURL)'")
        }

        var body: [String: Any] = [
            "model": request.model,
            "stream": true,
            "messages": request.messages.map(Self.openAIMessage),
        ]
        if let temperature = request.temperature { body["temperature"] = temperature }
        if let maxTokens = request.maxTokens { body["max_tokens"] = maxTokens }
        if let topP = request.topP { body["top_p"] = topP }
        if let frequencyPenalty = request.frequencyPenalty { body["frequency_penalty"] = frequencyPenalty }
        if let presencePenalty = request.presencePenalty { body["presence_penalty"] = presencePenalty }
        if let stop = request.stopSequences, !stop.isEmpty { body["stop"] = stop }
        if let seed = request.seed { body["seed"] = seed }
        body["stream_options"] = ["include_usage": true]
        if !request.tools.isEmpty {
            body["tools"] = request.tools.map(Self.toolSchema)
            body["tool_choice"] = "auto"
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        NetworkLog.logRequest(provider: displayName, request: urlRequest, body: body, full: debugLogging)
        logMissingKey()

        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw SphereError.protocolError("missing HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            var payload = ""
            for try await line in bytes.lines { payload += line }
            NetworkLog.logResponse(
                provider: displayName,
                url: url.absoluteString,
                status: http.statusCode,
                body: payload,
                full: true,
                isSuccess: false
            )
            throw SphereError.protocolError("HTTP \(http.statusCode) from \(displayName): \(payload)")
        }
        NetworkLog.logResponse(
            provider: displayName,
            url: url.absoluteString,
            status: http.statusCode,
            body: "",
            full: false,
            isSuccess: true
        )

        var accumulators: [Int: ToolAccumulator] = [:]
        var promptTokens: Int?
        var completionTokens: Int?

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard
                let data = payload.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            if let usage = json["usage"] as? [String: Any] {
                if let value = usage["prompt_tokens"] as? Int { promptTokens = value }
                if let value = usage["completion_tokens"] as? Int { completionTokens = value }
            }

            guard
                let choices = json["choices"] as? [[String: Any]],
                let delta = choices.first?["delta"] as? [String: Any]
            else {
                continue
            }

            if let content = delta["content"] as? String, !content.isEmpty {
                continuation.yield(.textDelta(content))
            }

            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                for call in toolCalls {
                    let index = call["index"] as? Int ?? 0
                    var accumulator = accumulators[index] ?? ToolAccumulator()
                    if let callID = call["id"] as? String, !callID.isEmpty {
                        accumulator.id = callID
                    }
                    if let function = call["function"] as? [String: Any] {
                        if let name = function["name"] as? String { accumulator.name += name }
                        if let arguments = function["arguments"] as? String { accumulator.arguments += arguments }
                    }
                    accumulators[index] = accumulator
                }
            }
        }

        for (_, accumulator) in accumulators.sorted(by: { $0.key < $1.key }) where !accumulator.name.isEmpty {
            continuation.yield(
                .toolCall(
                    LLMToolCall(
                        id: accumulator.id ?? UUID().uuidString,
                        name: accumulator.name,
                        arguments: JSONValue.parse(accumulator.arguments)
                    )
                )
            )
        }
        continuation.yield(.completed(promptTokens: promptTokens, completionTokens: completionTokens))
    }

    private func logMissingKey() {
        let key = apiKey ?? ""
        if key.isEmpty {
            SphereLog.http.write(
                "auth",
                "\(displayName): request sent WITHOUT API key (account \(config.id))"
            )
        }
    }

    private static func openAIMessage(_ message: LLMMessage) -> [String: Any] {
        switch message.role {
        case .system, .user:
            return ["role": message.role.rawValue, "content": message.content]
        case .assistant:
            var payload: [String: Any] = ["role": "assistant", "content": message.content]
            if !message.toolCalls.isEmpty {
                payload["tool_calls"] = message.toolCalls.map { call in
                    [
                        "id": call.id,
                        "type": "function",
                        "function": [
                            "name": call.name,
                            "arguments": call.arguments.prettyPrinted,
                        ],
                    ]
                }
            }
            return payload
        case .tool:
            return [
                "role": "tool",
                "tool_call_id": message.toolCallId ?? "",
                "content": message.content,
            ]
        }
    }

    private static func toolSchema(_ tool: ToolDefinition) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": tool.inputSchema?.anyValue ?? ["type": "object", "properties": [:] as [String: Any]],
            ],
        ]
    }
}
