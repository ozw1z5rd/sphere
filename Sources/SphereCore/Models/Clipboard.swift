import Foundation

/// One clipboard access performed through the built-in system tools.
public struct ClipboardEvent: Codable, Sendable, Identifiable {
    public var id: String
    public var sessionId: String?
    public var sessionNumber: Int?
    /// `read` or `write`.
    public var operation: String
    public var detail: String?
    public var allowed: Bool
    public var timestamp: Date

    public init(
        id: String = UUID().uuidString,
        sessionId: String? = nil,
        sessionNumber: Int? = nil,
        operation: String,
        detail: String? = nil,
        allowed: Bool = true,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.sessionNumber = sessionNumber
        self.operation = operation
        self.detail = detail
        self.allowed = allowed
        self.timestamp = timestamp
    }
}
