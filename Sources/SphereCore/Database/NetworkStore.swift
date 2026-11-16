import Foundation

public final class NetworkStore {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    // MARK: - Rules

    public func rules() throws -> [NetworkRule] {
        try database.query("SELECT * FROM network_rules ORDER BY created_at DESC").compactMap(decodeRule)
    }

    public func addRule(_ rule: NetworkRule) throws {
        try database.run(
            """
            INSERT INTO network_rules(id, value, kind, enabled, reason, created_at, last_blocked_at, blocked_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(rule.id),
                .text(rule.value),
                .text(rule.kind.rawValue),
                .integer(rule.enabled ? 1 : 0),
                rule.reason.map(SQLiteValue.text) ?? .null,
                DateCoding.value(rule.createdAt),
                DateCoding.optional(rule.lastBlockedAt),
                .integer(Int64(rule.blockedCount)),
            ]
        )
    }

    public func removeRule(id: String) throws {
        try database.run("DELETE FROM network_rules WHERE id = ?", [.text(id)])
    }

    public func setRuleEnabled(id: String, enabled: Bool) throws {
        try database.run(
            "UPDATE network_rules SET enabled = ? WHERE id = ?",
            [.integer(enabled ? 1 : 0), .text(id)]
        )
    }

    public func recordBlocked(ruleId: String) throws {
        try database.run(
            "UPDATE network_rules SET blocked_count = blocked_count + 1, last_blocked_at = ? WHERE id = ?",
            [DateCoding.value(Date()), .text(ruleId)]
        )
    }

    // MARK: - Events

    public func recordEvent(_ event: NetworkEvent) throws {
        try database.run(
            """
            INSERT INTO network_events(id, session_id, session_number, url, host, allowed, rule_id, detail, timestamp)
            VALUES (?, ?, (SELECT number FROM sessions WHERE id = ?), ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(event.id),
                event.sessionId.map(SQLiteValue.text) ?? .null,
                event.sessionId.map(SQLiteValue.text) ?? .null,
                .text(event.url),
                .text(event.host),
                .integer(event.allowed ? 1 : 0),
                event.ruleId.map(SQLiteValue.text) ?? .null,
                event.detail.map(SQLiteValue.text) ?? .null,
                DateCoding.value(event.timestamp),
            ]
        )
    }

    public func events(limit: Int = 200) throws -> [NetworkEvent] {
        try database.query(
            "SELECT * FROM network_events ORDER BY timestamp DESC LIMIT ?",
            [.integer(Int64(limit))]
        ).compactMap(decodeEvent)
    }

    public func count(sessionId: String) throws -> Int {
        try database.query(
            "SELECT COUNT(*) AS total FROM network_events WHERE session_id = ?",
            [.text(sessionId)]
        ).first?.int("total").map(Int.init) ?? 0
    }

    public func summary(since start: Date? = nil) throws -> NetworkSummary {
        let sql = """
        SELECT COUNT(*) AS total,
               COALESCE(SUM(CASE WHEN allowed = 1 THEN 1 ELSE 0 END), 0) AS allowed,
               COALESCE(SUM(CASE WHEN allowed = 0 THEN 1 ELSE 0 END), 0) AS blocked
        FROM network_events
        """
        let rows: [Row]
        if let start {
            rows = try database.query(sql + " WHERE timestamp >= ?", [DateCoding.value(start)])
        } else {
            rows = try database.query(sql)
        }
        guard let row = rows.first else { return .empty }
        return NetworkSummary(
            total: Int(row.int("total") ?? 0),
            allowed: Int(row.int("allowed") ?? 0),
            blocked: Int(row.int("blocked") ?? 0)
        )
    }

    // MARK: - Decoding

    private func decodeRule(_ row: Row) -> NetworkRule? {
        guard
            let id = row.string("id"),
            let value = row.string("value"),
            let kindRaw = row.string("kind"),
            let kind = NetworkRuleKind(rawValue: kindRaw),
            let createdAt = DateCoding.date(row["created_at"])
        else { return nil }
        return NetworkRule(
            id: id,
            value: value,
            kind: kind,
            enabled: row.bool("enabled") ?? true,
            reason: row.string("reason"),
            createdAt: createdAt,
            lastBlockedAt: DateCoding.date(row["last_blocked_at"]),
            blockedCount: Int(row.int("blocked_count") ?? 0)
        )
    }

    private func decodeEvent(_ row: Row) -> NetworkEvent? {
        guard
            let id = row.string("id"),
            let url = row.string("url"),
            let host = row.string("host"),
            let timestamp = DateCoding.date(row["timestamp"])
        else { return nil }
        return NetworkEvent(
            id: id,
            sessionId: row.string("session_id"),
            sessionNumber: row.int("session_number").map(Int.init),
            url: url,
            host: host,
            allowed: row.bool("allowed") ?? false,
            ruleId: row.string("rule_id"),
            detail: row.string("detail"),
            timestamp: timestamp
        )
    }
}
