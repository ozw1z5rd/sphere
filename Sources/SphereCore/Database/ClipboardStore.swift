import Foundation

/// Persistent log of clipboard reads/writes made by the system tools.
public final class ClipboardStore {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func record(_ event: ClipboardEvent) throws {
        try database.run(
            """
            INSERT INTO clipboard_events(id, session_id, operation, detail, allowed, timestamp)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            [
                .text(event.id),
                event.sessionId.map(SQLiteValue.text) ?? .null,
                .text(event.operation),
                event.detail.map(SQLiteValue.text) ?? .null,
                .integer(event.allowed ? 1 : 0),
                DateCoding.value(event.timestamp),
            ]
        )
    }

    public func events(sessionId: String? = nil, limit: Int = 200) throws -> [ClipboardEvent] {
        let sql: String
        let values: [SQLiteValue]
        if let sessionId {
            sql = "SELECT * FROM clipboard_events WHERE session_id = ? ORDER BY timestamp DESC LIMIT ?"
            values = [.text(sessionId), .integer(Int64(limit))]
        } else {
            sql = "SELECT * FROM clipboard_events ORDER BY timestamp DESC LIMIT ?"
            values = [.integer(Int64(limit))]
        }
        return try database.query(sql, values).compactMap(decode)
    }

    public func count(sessionId: String? = nil, allowedOnly: Bool = false) throws -> Int {
        var clauses: [String] = []
        var values: [SQLiteValue] = []
        if let sessionId {
            clauses.append("session_id = ?")
            values.append(.text(sessionId))
        }
        if allowedOnly {
            clauses.append("allowed = 1")
        }
        let whereClause = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
        let sql = "SELECT COUNT(*) AS total FROM clipboard_events" + whereClause
        return try database.query(sql, values).first?.int("total").map(Int.init) ?? 0
    }

    private func decode(_ row: Row) -> ClipboardEvent? {
        guard
            let id = row.string("id"),
            let operation = row.string("operation"),
            let timestamp = DateCoding.date(row["timestamp"])
        else { return nil }
        return ClipboardEvent(
            id: id,
            sessionId: row.string("session_id"),
            operation: operation,
            detail: row.string("detail"),
            allowed: row.bool("allowed") ?? true,
            timestamp: timestamp
        )
    }
}
