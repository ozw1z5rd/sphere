import Foundation

public enum FileOperation: String, Codable, CaseIterable, Sendable {
    case read
    case write
    case edit
    case list
    case glob
    case grep

    public var isWrite: Bool {
        switch self {
        case .write, .edit: return true
        default: return false
        }
    }
}

public struct PathGrant: Codable, Sendable, Identifiable {
    public var id: String
    public var path: String
    public var mode: FileAccessMode
    public var recursive: Bool
    public var scope: GrantScope
    public var moduleId: String?
    public var createdAt: Date
    public var lastUsedAt: Date?
    public var readCount: Int
    public var writeCount: Int

    public init(
        id: String = UUID().uuidString,
        path: String,
        mode: FileAccessMode,
        recursive: Bool = true,
        scope: GrantScope = .persistent,
        moduleId: String? = nil,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        readCount: Int = 0,
        writeCount: Int = 0
    ) {
        self.id = id
        self.path = path
        self.mode = mode
        self.recursive = recursive
        self.scope = scope
        self.moduleId = moduleId
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.readCount = readCount
        self.writeCount = writeCount
    }
}

public struct AccessEvent: Codable, Sendable, Identifiable {
    public var id: String
    public var grantId: String?
    public var sessionId: String?
    public var sessionNumber: Int?
    public var moduleId: String
    public var path: String
    public var operation: FileOperation
    public var allowed: Bool
    public var detail: String?
    public var timestamp: Date

    public init(
        id: String = UUID().uuidString,
        grantId: String? = nil,
        sessionId: String? = nil,
        sessionNumber: Int? = nil,
        moduleId: String,
        path: String,
        operation: FileOperation,
        allowed: Bool,
        detail: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.grantId = grantId
        self.sessionId = sessionId
        self.sessionNumber = sessionNumber
        self.moduleId = moduleId
        self.path = path
        self.operation = operation
        self.allowed = allowed
        self.detail = detail
        self.timestamp = timestamp
    }
}

public struct AccessSummary: Sendable, Equatable {
    public var total: Int
    public var reads: Int
    public var writes: Int
    public var denied: Int

    public init(total: Int = 0, reads: Int = 0, writes: Int = 0, denied: Int = 0) {
        self.total = total
        self.reads = reads
        self.writes = writes
        self.denied = denied
    }

    public static let empty = AccessSummary()
}

public struct ScreenGrant: Codable, Sendable, Identifiable {
    public var id: String
    public var bundleId: String?
    public var appName: String
    public var windowTitle: String?
    public var windowId: UInt32?
    public var enabled: Bool
    public var createdAt: Date
    public var lastUsedAt: Date?
    public var captureCount: Int

    public init(
        id: String = UUID().uuidString,
        bundleId: String? = nil,
        appName: String,
        windowTitle: String? = nil,
        windowId: UInt32? = nil,
        enabled: Bool = true,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        captureCount: Int = 0
    ) {
        self.id = id
        self.bundleId = bundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.windowId = windowId
        self.enabled = enabled
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.captureCount = captureCount
    }
}
