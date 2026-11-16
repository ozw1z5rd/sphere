import Foundation

public enum NetworkRuleKind: String, Codable, CaseIterable, Sendable {
    case url
    case domain
    case ip

    public var label: String {
        switch self {
        case .url: return "URL"
        case .domain: return "Domain"
        case .ip: return "IP / CIDR"
        }
    }
}

public struct NetworkRule: Codable, Sendable, Identifiable {
    public var id: String
    public var value: String
    public var kind: NetworkRuleKind
    public var enabled: Bool
    public var reason: String?
    public var createdAt: Date
    public var lastBlockedAt: Date?
    public var blockedCount: Int

    public init(
        id: String = UUID().uuidString,
        value: String,
        kind: NetworkRuleKind,
        enabled: Bool = true,
        reason: String? = nil,
        createdAt: Date = Date(),
        lastBlockedAt: Date? = nil,
        blockedCount: Int = 0
    ) {
        self.id = id
        self.value = value
        self.kind = kind
        self.enabled = enabled
        self.reason = reason
        self.createdAt = createdAt
        self.lastBlockedAt = lastBlockedAt
        self.blockedCount = blockedCount
    }
}

public struct NetworkEvent: Codable, Sendable, Identifiable {
    public var id: String
    public var sessionId: String?
    public var sessionNumber: Int?
    public var url: String
    public var host: String
    public var allowed: Bool
    public var ruleId: String?
    public var detail: String?
    public var timestamp: Date

    public init(
        id: String = UUID().uuidString,
        sessionId: String? = nil,
        sessionNumber: Int? = nil,
        url: String,
        host: String,
        allowed: Bool,
        ruleId: String? = nil,
        detail: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.sessionNumber = sessionNumber
        self.url = url
        self.host = host
        self.allowed = allowed
        self.ruleId = ruleId
        self.detail = detail
        self.timestamp = timestamp
    }
}

public struct NetworkSummary: Sendable, Equatable {
    public var total: Int
    public var allowed: Int
    public var blocked: Int

    public init(total: Int = 0, allowed: Int = 0, blocked: Int = 0) {
        self.total = total
        self.allowed = allowed
        self.blocked = blocked
    }

    public static let empty = NetworkSummary()
}
