import Foundation
import SphereCore
import SphereLLM
import SphereTools

public enum AgentEvent: Sendable {
    case textDelta(String)
    case assistantMessage(String)
    case toolCallStarted(ToolCallRecord)
    case toolCallFinished(ToolCallRecord)
    case usage(SessionUsage)
    case completed(String)
}

/// Runs the model/tool loop: stream text, execute tool calls through the
/// router, feed results back and repeat until the model stops calling tools.
public final class AgentRunner: @unchecked Sendable {
    private let provider: LLMProvider
    private let router: ToolRouter
    private let sessions: SessionStore
    private let maxSteps: Int
    /// Set once per run so a missing price entry is logged a single time.
    private var warnedUnknownPricing = false

    public init(provider: LLMProvider, router: ToolRouter, sessions: SessionStore, maxSteps: Int = 12) {
        self.provider = provider
        self.router = router
        self.sessions = sessions
        self.maxSteps = maxSteps
    }

    public func run(
        sessionId: String,
        userText: String,
        displayText: String? = nil,
        attachments: [ChatAttachment] = [],
        systemPrompt: String,
        history: [LLMMessage] = [],
        model: String,
        options: GenerationOptions = GenerationOptions()
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.execute(
                        sessionId: sessionId,
                        userText: userText,
                        displayText: displayText ?? userText,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        history: history,
                        model: model,
                        options: options,
                        continuation: continuation
                    )
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

    private func execute(
        sessionId: String,
        userText: String,
        displayText: String,
        attachments: [ChatAttachment],
        systemPrompt: String,
        history: [LLMMessage],
        model: String,
        options: GenerationOptions,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws {
        try sessions.appendMessage(
            ChatMessage(
                sessionId: sessionId,
                role: .user,
                content: displayText,
                attachments: attachments
            )
        )

        var conversation: [LLMMessage] = []
        if !systemPrompt.isEmpty {
            conversation.append(LLMMessage(role: .system, content: systemPrompt))
        }
        conversation.append(contentsOf: LLMHistory.sanitized(history))
        conversation.append(LLMMessage(role: .user, content: userText))

        for _ in 0..<maxSteps {
            // Refresh per step so tools disabled/denied mid-run disappear from
            // the catalog instead of being advertised and then rejected.
            let tools = await router.definitions()
            let request = LLMRequest(
                model: model,
                messages: conversation,
                tools: tools,
                options: options
            )

            var assistantText = ""
            var toolCalls: [LLMToolCall] = []

            for try await event in provider.stream(request: request) {
                switch event {
                case .textDelta(let delta):
                    assistantText += delta
                    continuation.yield(.textDelta(delta))
                case .toolCall(let call):
                    toolCalls.append(call)
                case .completed(let usage):
                    if usage.promptTokens != nil || usage.completionTokens != nil {
                        let prompt = usage.promptTokens ?? 0
                        let completion = usage.completionTokens ?? 0
                        let cost = Pricing.cost(
                            model: model,
                            promptTokens: prompt,
                            completionTokens: completion,
                            cacheHitTokens: usage.cacheHitTokens,
                            cacheMissTokens: usage.cacheMissTokens
                        )
                        if cost == nil, !warnedUnknownPricing {
                            // Unknown model: the tokens are still counted, but
                            // the cost stays at zero. Make it visible in the
                            // HTTP log instead of silently reporting $0.
                            warnedUnknownPricing = true
                            SphereLog.http.write(
                                "pricing",
                                "no price entry for model '\(model)' — session cost will stay at 0"
                            )
                        }
                        if let usage = try? sessions.recordUsage(
                            sessionId: sessionId,
                            promptTokens: prompt,
                            completionTokens: completion,
                            costUSD: cost ?? 0
                        ) {
                            continuation.yield(.usage(usage))
                        }
                    }
                }
            }

            if !assistantText.isEmpty || !toolCalls.isEmpty {
                try sessions.appendMessage(
                    ChatMessage(
                        sessionId: sessionId,
                        role: .assistant,
                        content: assistantText,
                        toolCalls: toolCalls
                    )
                )
                if !assistantText.isEmpty {
                    continuation.yield(.assistantMessage(assistantText))
                }
            }

            guard !toolCalls.isEmpty else {
                continuation.yield(.completed(assistantText))
                return
            }

            conversation.append(
                LLMMessage(role: .assistant, content: assistantText, toolCalls: toolCalls)
            )

            for call in toolCalls {
                let definition = await router.definition(named: call.name)
                var record = ToolCallRecord(
                    sessionId: sessionId,
                    moduleId: definition?.moduleId ?? "unknown",
                    toolName: definition?.originalName ?? call.name,
                    argumentsJSON: call.arguments.prettyPrinted,
                    status: .running
                )
                try sessions.recordToolCall(record)
                continuation.yield(.toolCallStarted(record))

                do {
                    let outcome = try await router.invoke(name: call.name, arguments: call.arguments, sessionId: sessionId)
                    record.status = outcome.isError ? .failed : .succeeded
                    record.resultJSON = outcome.text
                    record.finishedAt = Date()
                    try sessions.recordToolCall(record)
                    continuation.yield(.toolCallFinished(record))

                    conversation.append(
                        LLMMessage(role: .tool, content: outcome.text, toolCallId: call.id, name: call.name)
                    )
                    try sessions.appendMessage(
                        ChatMessage(
                            sessionId: sessionId,
                            role: .tool,
                            content: outcome.text,
                            toolCallId: call.id,
                            name: call.name
                        )
                    )
                } catch {
                    record.status = .failed
                    record.resultJSON = error.localizedDescription
                    record.finishedAt = Date()
                    try sessions.recordToolCall(record)
                    continuation.yield(.toolCallFinished(record))

                    conversation.append(
                        LLMMessage(
                            role: .tool,
                            content: "Error: \(error.localizedDescription)",
                            toolCallId: call.id,
                            name: call.name
                        )
                    )
                    try sessions.appendMessage(
                        ChatMessage(
                            sessionId: sessionId,
                            role: .tool,
                            content: "Error: \(error.localizedDescription)",
                            toolCallId: call.id,
                            name: call.name
                        )
                    )
                }
            }
        }

        throw SphereError.protocolError("agent exceeded \(maxSteps) steps without finishing")
    }
}
