import Foundation
import SphereCore

public enum LLMRole: String, Sendable {
    case system
    case user
    case assistant
    case tool
}

public struct LLMMessage: Sendable {
    public var role: LLMRole
    public var content: String
    public var toolCallId: String?
    public var toolCalls: [LLMToolCall]
    public var name: String?

    public init(
        role: LLMRole,
        content: String,
        toolCallId: String? = nil,
        toolCalls: [LLMToolCall] = [],
        name: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
        self.name = name
    }
}

public struct GenerationOptions: Sendable {
    public var temperature: Double?
    public var maxTokens: Int?
    public var topP: Double?
    public var topK: Int?
    public var frequencyPenalty: Double?
    public var presencePenalty: Double?
    public var stopSequences: [String]?
    public var seed: Int?

    public init(
        temperature: Double? = 0.2,
        maxTokens: Int? = 4096,
        topP: Double? = nil,
        topK: Int? = nil,
        frequencyPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        stopSequences: [String]? = nil,
        seed: Int? = nil
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.topK = topK
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.stopSequences = stopSequences
        self.seed = seed
    }

    public init(provider: ProviderConfig) {
        self.init(
            temperature: provider.temperature,
            maxTokens: provider.maxTokens,
            topP: provider.topP,
            topK: provider.topK,
            frequencyPenalty: provider.frequencyPenalty,
            presencePenalty: provider.presencePenalty,
            stopSequences: provider.stopSequences,
            seed: provider.seed
        )
    }
}

public struct LLMRequest: Sendable {
    public var model: String
    public var messages: [LLMMessage]
    public var tools: [ToolDefinition]
    public var temperature: Double?
    public var maxTokens: Int?
    public var topP: Double?
    public var topK: Int?
    public var frequencyPenalty: Double?
    public var presencePenalty: Double?
    public var stopSequences: [String]?
    public var seed: Int?

    public init(
        model: String,
        messages: [LLMMessage],
        tools: [ToolDefinition] = [],
        options: GenerationOptions = GenerationOptions()
    ) {
        self.model = model
        self.messages = messages
        self.tools = tools
        self.temperature = options.temperature
        self.maxTokens = options.maxTokens
        self.topP = options.topP
        self.topK = options.topK
        self.frequencyPenalty = options.frequencyPenalty
        self.presencePenalty = options.presencePenalty
        self.stopSequences = options.stopSequences
        self.seed = options.seed
    }
}

public enum LLMEvent: Sendable {
    case textDelta(String)
    case toolCall(LLMToolCall)
    case completed(promptTokens: Int?, completionTokens: Int?)
}

public struct LLMUsage: Sendable {
    public var promptTokens: Int?
    public var completionTokens: Int?

    public init(promptTokens: Int? = nil, completionTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

/// Helpers to make a persisted conversation acceptable to strict providers
/// (DeepSeek, OpenAI) that require each `tool` message to directly follow an
/// assistant message declaring the matching `tool_calls`.
public enum LLMHistory {
    public static func sanitized(_ history: [LLMMessage]) -> [LLMMessage] {
        var result: [LLMMessage] = []
        var index = 0
        while index < history.count {
            let message = history[index]

            guard message.role == .assistant, !message.toolCalls.isEmpty else {
                if message.role != .tool {
                    result.append(message)
                }
                index += 1
                continue
            }

            var responses: [String: LLMMessage] = [:]
            var cursor = index + 1
            while cursor < history.count, history[cursor].role == .tool {
                let response = history[cursor]
                if let id = response.toolCallId, responses[id] == nil {
                    responses[id] = response
                }
                cursor += 1
            }

            let answered = message.toolCalls.filter { responses[$0.id] != nil }
            if answered.isEmpty {
                if !message.content.isEmpty {
                    result.append(LLMMessage(role: .assistant, content: message.content))
                }
            } else {
                result.append(
                    LLMMessage(role: .assistant, content: message.content, toolCalls: answered)
                )
                for call in answered {
                    if let response = responses[call.id] {
                        result.append(response)
                    }
                }
            }
            index = cursor
        }
        return result
    }
}
