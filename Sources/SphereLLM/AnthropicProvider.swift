import Foundation
import SphereCore

public final class AnthropicProvider: LLMProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String

    private let config: ProviderConfig
    private let apiKey: String?
    private let debugLogging: Bool
    private let session: URLSession

    private struct ToolAccumulator {
        var id: String?
        var name: String = ""
        var inputJSON: String = ""
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
        let root = base.hasSuffix("/v1") ? base : base + "/v1"
        guard let url = URL(string: root + "/models?limit=1000") else {
            throw SphereError.notConfigured("invalid provider base URL '\(config.baseURL)'")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let apiKey, !apiKey.isEmpty {
            urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
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
        let formatter = ISO8601DateFormatter()
        return items.compactMap { item -> LLMModel? in
            guard let id = item["id"] as? String else { return nil }
            let created = (item["created_at"] as? String).flatMap { formatter.date(from: $0) }
            return LLMModel(id: id, displayName: item["display_name"] as? String, created: created)
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    private func run(request: LLMRequest, continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation) async throws {
        let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
        guard let url = URL(string: base + "/v1/messages") else {
            throw SphereError.notConfigured("invalid provider base URL '\(config.baseURL)'")
        }

        let systemText = request.messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")

        var body: [String: Any] = [
            "model": request.model,
            "max_tokens": request.maxTokens ?? 4096,
            "stream": true,
            "messages": Self.anthropicMessages(request.messages),
        ]
        if !systemText.isEmpty { body["system"] = systemText }
        if let temperature = request.temperature { body["temperature"] = temperature }
        if let topP = request.topP { body["top_p"] = topP }
        if let topK = request.topK { body["top_k"] = topK }
        if let stop = request.stopSequences, !stop.isEmpty { body["stop_sequences"] = stop }
        if !request.tools.isEmpty {
            body["tools"] = request.tools.map { tool in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": tool.inputSchema?.anyValue ?? ["type": "object", "properties": [:] as [String: Any]],
                ]
            }
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let apiKey, !apiKey.isEmpty {
            urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
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
            guard
                !payload.isEmpty,
                let data = payload.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = json["type"] as? String
            else {
                continue
            }

            switch type {
            case "message_start":
                if let usage = json["message"] as? [String: Any], let input = usage["usage"] as? [String: Any] {
                    promptTokens = input["input_tokens"] as? Int
                }
            case "content_block_start":
                let index = json["index"] as? Int ?? 0
                if let block = json["content_block"] as? [String: Any], block["type"] as? String == "tool_use" {
                    var accumulator = ToolAccumulator()
                    accumulator.id = block["id"] as? String
                    accumulator.name = block["name"] as? String ?? ""
                    accumulators[index] = accumulator
                }
            case "content_block_delta":
                let index = json["index"] as? Int ?? 0
                guard let delta = json["delta"] as? [String: Any], let deltaType = delta["type"] as? String else { continue }
                switch deltaType {
                case "text_delta":
                    if let text = delta["text"] as? String, !text.isEmpty {
                        continuation.yield(.textDelta(text))
                    }
                case "input_json_delta":
                    if let partial = delta["partial_json"] as? String, var accumulator = accumulators[index] {
                        accumulator.inputJSON += partial
                        accumulators[index] = accumulator
                    }
                default:
                    break
                }
            case "content_block_stop":
                let index = json["index"] as? Int ?? 0
                if let accumulator = accumulators.removeValue(forKey: index), !accumulator.name.isEmpty {
                    continuation.yield(
                        .toolCall(
                            LLMToolCall(
                                id: accumulator.id ?? UUID().uuidString,
                                name: accumulator.name,
                                arguments: JSONValue.parse(accumulator.inputJSON.isEmpty ? "{}" : accumulator.inputJSON)
                            )
                        )
                    )
                }
            case "message_delta":
                if let usage = json["usage"] as? [String: Any] {
                    completionTokens = usage["output_tokens"] as? Int
                }
            case "error":
                if let error = json["error"] as? [String: Any] {
                    throw SphereError.protocolError("\(error["type"] ?? "error"): \(error["message"] ?? "unknown")")
                }
            case "message_stop":
                break
            default:
                break
            }
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

    private static func anthropicMessages(_ messages: [LLMMessage]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for message in messages where message.role != .system {
            switch message.role {
            case .user:
                result.append(["role": "user", "content": message.content])
            case .assistant:
                var blocks: [[String: Any]] = []
                if !message.content.isEmpty {
                    blocks.append(["type": "text", "text": message.content])
                }
                for call in message.toolCalls {
                    blocks.append([
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.name,
                        "input": call.arguments.anyValue,
                    ])
                }
                result.append(["role": "assistant", "content": blocks])
            case .tool:
                result.append([
                    "role": "user",
                    "content": [
                        [
                            "type": "tool_result",
                            "tool_use_id": message.toolCallId ?? "",
                            "content": message.content,
                        ]
                    ],
                ])
            case .system:
                break
            }
        }
        return result
    }
}
