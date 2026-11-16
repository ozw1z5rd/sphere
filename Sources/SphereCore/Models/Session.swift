import Foundation

public struct Session: Codable, Sendable, Identifiable {
    public var id: String
    /// Stable progressive number assigned at creation (shown as `#N`).
    public var number: Int
    public var title: String
    public var providerId: String?
    public var model: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var promptTokens: Int
    public var completionTokens: Int
    public var costUSD: Double

    public var usage: SessionUsage {
        SessionUsage(promptTokens: promptTokens, completionTokens: completionTokens, costUSD: costUSD)
    }

    public init(
        id: String = UUID().uuidString,
        number: Int = 0,
        title: String = "New session",
        providerId: String? = nil,
        model: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        costUSD: Double = 0
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.providerId = providerId
        self.model = model
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.costUSD = costUSD
    }
}

public struct SessionUsage: Sendable, Equatable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var costUSD: Double

    public var totalTokens: Int { promptTokens + completionTokens }

    public init(promptTokens: Int = 0, completionTokens: Int = 0, costUSD: Double = 0) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.costUSD = costUSD
    }

    public static let zero = SessionUsage()
}

public enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public struct ChatAttachment: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var path: String
    public var name: String
    public var type: String
    public var isImage: Bool

    public init(
        id: String = UUID().uuidString,
        path: String,
        name: String,
        type: String,
        isImage: Bool = false
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.type = type
        self.isImage = isImage
    }
}

public struct ChatMessage: Codable, Sendable, Identifiable {
    public var id: String
    public var sessionId: String
    public var role: MessageRole
    public var content: String
    public var toolCallId: String?
    public var toolCalls: [LLMToolCall]
    public var name: String?
    public var attachments: [ChatAttachment]
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        sessionId: String,
        role: MessageRole,
        content: String,
        toolCallId: String? = nil,
        toolCalls: [LLMToolCall] = [],
        name: String? = nil,
        attachments: [ChatAttachment] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
        self.name = name
        self.attachments = attachments
        self.createdAt = createdAt
    }
}

public enum ToolCallStatus: String, Codable, Sendable {
    case pending
    case running
    case succeeded
    case failed
    case denied
}

public struct ToolCallRecord: Codable, Sendable, Identifiable {
    public var id: String
    public var sessionId: String
    public var sessionNumber: Int?
    public var moduleId: String
    public var toolName: String
    public var argumentsJSON: String
    public var resultJSON: String?
    public var status: ToolCallStatus
    public var startedAt: Date
    public var finishedAt: Date?

    public init(
        id: String = UUID().uuidString,
        sessionId: String,
        sessionNumber: Int? = nil,
        moduleId: String,
        toolName: String,
        argumentsJSON: String = "{}",
        resultJSON: String? = nil,
        status: ToolCallStatus = .pending,
        startedAt: Date = Date(),
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.sessionNumber = sessionNumber
        self.moduleId = moduleId
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.resultJSON = resultJSON
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
