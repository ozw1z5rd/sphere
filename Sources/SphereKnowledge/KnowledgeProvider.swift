import Foundation

public struct KnowledgeSource: Sendable, Identifiable {
    public var id: String
    public var title: String
    public var content: String
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, title: String, content: String, metadata: [String: String] = [:]) {
        self.id = id
        self.title = title
        self.content = content
        self.metadata = metadata
    }
}

public struct KnowledgeHit: Sendable, Identifiable {
    public var id: String
    public var sourceId: String
    public var title: String
    public var chunk: String
    public var score: Double

    public init(id: String = UUID().uuidString, sourceId: String, title: String, chunk: String, score: Double) {
        self.id = id
        self.sourceId = sourceId
        self.title = title
        self.chunk = chunk
        self.score = score
    }
}

public struct KnowledgeStats: Sendable {
    public var documents: Int
    public var chunks: Int

    public init(documents: Int = 0, chunks: Int = 0) {
        self.documents = documents
        self.chunks = chunks
    }
}

/// Contract for knowledge-base plugins. A Phase 2 implementation will add
/// embeddings and a vector index; the interface is stable from day one.
public protocol KnowledgeProvider: AnyObject, Sendable {
    var id: String { get }
    var displayName: String { get }
    func ingest(_ source: KnowledgeSource) async throws
    func search(query: String, limit: Int) async throws -> [KnowledgeHit]
    func stats() async throws -> KnowledgeStats
}

/// Placeholder provider that does simple substring matching. Replace with an
/// FTS5/embedding-backed implementation in Phase 2.
public final class InMemoryKnowledgeProvider: KnowledgeProvider, @unchecked Sendable {
    public let id = "sphere.knowledge.memory"
    public let displayName = "In-memory Knowledge (stub)"

    private var sources: [KnowledgeSource] = []
    private let lock = NSLock()

    public init() {}

    public func ingest(_ source: KnowledgeSource) async throws {
        lock.withLock { sources.append(source) }
    }

    public func search(query: String, limit: Int = 5) async throws -> [KnowledgeHit] {
        let snapshot = lock.withLock { sources }

        guard !query.isEmpty else { return [] }
        let needle = query.lowercased()
        return snapshot.compactMap { source -> KnowledgeHit? in
            guard let range = source.content.lowercased().range(of: needle) else { return nil }
            let start = source.content.index(range.lowerBound, offsetBy: -80, limitedBy: source.content.startIndex) ?? source.content.startIndex
            let end = source.content.index(range.upperBound, offsetBy: 120, limitedBy: source.content.endIndex) ?? source.content.endIndex
            return KnowledgeHit(
                sourceId: source.id,
                title: source.title,
                chunk: String(source.content[start..<end]),
                score: 1.0
            )
        }
        .prefix(limit)
        .map { $0 }
    }

    public func stats() async throws -> KnowledgeStats {
        let count = lock.withLock { sources.count }
        return KnowledgeStats(documents: count, chunks: count)
    }
}
