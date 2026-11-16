import Foundation

public final class PermissionStore {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    // MARK: - Path grants

    public func pathGrants() throws -> [PathGrant] {
        try database.query("SELECT * FROM path_grants ORDER BY path").compactMap(decodeGrant)
    }

    public func addPathGrant(_ grant: PathGrant) throws {
        try database.run(
            """
            INSERT INTO path_grants(id, path, mode, recursive, scope, module_id, created_at, last_used_at, read_count, write_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(grant.id),
                .text(grant.path),
                .text(grant.mode.rawValue),
                .integer(grant.recursive ? 1 : 0),
                .text(grant.scope.rawValue),
                grant.moduleId.map(SQLiteValue.text) ?? .null,
                DateCoding.value(grant.createdAt),
                DateCoding.optional(grant.lastUsedAt),
                .integer(Int64(grant.readCount)),
                .integer(Int64(grant.writeCount)),
            ]
        )
    }

    public func updatePathGrantMode(id: String, mode: FileAccessMode) throws {
        try database.run("UPDATE path_grants SET mode = ? WHERE id = ?", [.text(mode.rawValue), .text(id)])
    }

    public func removePathGrant(id: String) throws {
        try database.run("DELETE FROM path_grants WHERE id = ?", [.text(id)])
    }

    public func recordAccess(_ event: AccessEvent) throws {
        try database.run(
            """
            INSERT INTO access_events(id, grant_id, session_id, session_number, module_id, path, operation, allowed, detail, timestamp)
            VALUES (?, ?, ?, (SELECT number FROM sessions WHERE id = ?), ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(event.id),
                event.grantId.map(SQLiteValue.text) ?? .null,
                event.sessionId.map(SQLiteValue.text) ?? .null,
                event.sessionId.map(SQLiteValue.text) ?? .null,
                .text(event.moduleId),
                .text(event.path),
                .text(event.operation.rawValue),
                .integer(event.allowed ? 1 : 0),
                event.detail.map(SQLiteValue.text) ?? .null,
                DateCoding.value(event.timestamp),
            ]
        )

        guard event.allowed, let grantId = event.grantId else { return }
        let column = event.operation.isWrite ? "write_count" : "read_count"
        try database.run(
            "UPDATE path_grants SET \(column) = \(column) + 1, last_used_at = ? WHERE id = ?",
            [DateCoding.value(event.timestamp), .text(grantId)]
        )
    }

    public func accessEvents(limit: Int = 200) throws -> [AccessEvent] {
        try database.query(
            "SELECT * FROM access_events ORDER BY timestamp DESC LIMIT ?",
            [.integer(Int64(limit))]
        ).compactMap(decodeEvent)
    }

    /// Aggregated access counters, optionally scoped from a start date.
    public func accessSummary(since start: Date?) throws -> AccessSummary {
        let sql = """
        SELECT COUNT(*) AS total,
               COALESCE(SUM(CASE WHEN operation IN ('read','list','glob','grep') THEN 1 ELSE 0 END), 0) AS reads,
               COALESCE(SUM(CASE WHEN operation IN ('write','edit') THEN 1 ELSE 0 END), 0) AS writes,
               COALESCE(SUM(CASE WHEN allowed = 0 THEN 1 ELSE 0 END), 0) AS denied
        FROM access_events
        """
        let rows: [Row]
        if let start {
            rows = try database.query(sql + " WHERE timestamp >= ?", [DateCoding.value(start)])
        } else {
            rows = try database.query(sql)
        }
        guard let row = rows.first else { return .empty }
        return AccessSummary(
            total: Int(row.int("total") ?? 0),
            reads: Int(row.int("reads") ?? 0),
            writes: Int(row.int("writes") ?? 0),
            denied: Int(row.int("denied") ?? 0)
        )
    }

    public func accessEvents(forPath path: String, limit: Int = 200) throws -> [AccessEvent] {
        try database.query(
            "SELECT * FROM access_events WHERE path = ? ORDER BY timestamp DESC LIMIT ?",
            [.text(path), .integer(Int64(limit))]
        ).compactMap(decodeEvent)
    }

    // MARK: - Screen grants

    public func screenGrants() throws -> [ScreenGrant] {
        try database.query("SELECT * FROM screen_grants ORDER BY app_name").compactMap(decodeScreenGrant)
    }

    public func addScreenGrant(_ grant: ScreenGrant) throws {
        try database.run(
            """
            INSERT INTO screen_grants(id, bundle_id, app_name, window_title, window_id, enabled, created_at, last_used_at, capture_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(grant.id),
                grant.bundleId.map(SQLiteValue.text) ?? .null,
                .text(grant.appName),
                grant.windowTitle.map(SQLiteValue.text) ?? .null,
                grant.windowId.map { .integer(Int64($0)) } ?? .null,
                .integer(grant.enabled ? 1 : 0),
                DateCoding.value(grant.createdAt),
                DateCoding.optional(grant.lastUsedAt),
                .integer(Int64(grant.captureCount)),
            ]
        )
    }

    public func setScreenGrantEnabled(id: String, enabled: Bool) throws {
        try database.run("UPDATE screen_grants SET enabled = ? WHERE id = ?", [.integer(enabled ? 1 : 0), .text(id)])
    }

    public func removeScreenGrant(id: String) throws {
        try database.run("DELETE FROM screen_grants WHERE id = ?", [.text(id)])
    }

    public func recordScreenCapture(grantId: String) throws {
        try database.run(
            "UPDATE screen_grants SET capture_count = capture_count + 1, last_used_at = ? WHERE id = ?",
            [DateCoding.value(Date()), .text(grantId)]
        )
    }

    // MARK: - Decoding

    private func decodeGrant(_ row: Row) -> PathGrant? {
        guard
            let id = row.string("id"),
            let path = row.string("path"),
            let modeRaw = row.string("mode"),
            let mode = FileAccessMode(rawValue: modeRaw),
            let scopeRaw = row.string("scope"),
            let scope = GrantScope(rawValue: scopeRaw),
            let createdAt = DateCoding.date(row["created_at"])
        else { return nil }
        return PathGrant(
            id: id,
            path: path,
            mode: mode,
            recursive: row.bool("recursive") ?? true,
            scope: scope,
            moduleId: row.string("module_id"),
            createdAt: createdAt,
            lastUsedAt: DateCoding.date(row["last_used_at"]),
            readCount: Int(row.int("read_count") ?? 0),
            writeCount: Int(row.int("write_count") ?? 0)
        )
    }

    private func decodeEvent(_ row: Row) -> AccessEvent? {
        guard
            let id = row.string("id"),
            let moduleId = row.string("module_id"),
            let path = row.string("path"),
            let operationRaw = row.string("operation"),
            let operation = FileOperation(rawValue: operationRaw),
            let timestamp = DateCoding.date(row["timestamp"])
        else { return nil }
        return AccessEvent(
            id: id,
            grantId: row.string("grant_id"),
            sessionId: row.string("session_id"),
            sessionNumber: row.int("session_number").map(Int.init),
            moduleId: moduleId,
            path: path,
            operation: operation,
            allowed: row.bool("allowed") ?? false,
            detail: row.string("detail"),
            timestamp: timestamp
        )
    }

    private func decodeScreenGrant(_ row: Row) -> ScreenGrant? {
        guard
            let id = row.string("id"),
            let appName = row.string("app_name"),
            let createdAt = DateCoding.date(row["created_at"])
        else { return nil }
        return ScreenGrant(
            id: id,
            bundleId: row.string("bundle_id"),
            appName: appName,
            windowTitle: row.string("window_title"),
            windowId: row.int("window_id").map { UInt32($0) },
            enabled: row.bool("enabled") ?? true,
            createdAt: createdAt,
            lastUsedAt: DateCoding.date(row["last_used_at"]),
            captureCount: Int(row.int("capture_count") ?? 0)
        )
    }
}
