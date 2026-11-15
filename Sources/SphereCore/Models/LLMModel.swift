import Foundation

public struct LLMModel: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var displayName: String?
    public var ownedBy: String?
    public var created: Date?
    public var contextLength: Int?

    public init(
        id: String,
        displayName: String? = nil,
        ownedBy: String? = nil,
        created: Date? = nil,
        contextLength: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.ownedBy = ownedBy
        self.created = created
        self.contextLength = contextLength
    }

    public var label: String {
        if let displayName, !displayName.isEmpty, displayName != id {
            return "\(displayName) (\(id))"
        }
        return id
    }
}
