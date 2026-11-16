import Foundation

public final class SessionStore {
    private let database: Database
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: Database) {
        self.database = database
    }

    public func createSession(title: String = "New session", providerId: String? = nil, model: String? = nil) throws -> Session {
        var session = Session(title: title, providerId: providerId, model: model)
        try database.run(
            """
            INSERT INTO sessions(id, title, provider_id, model, created_at, updated_at, number)
            VALUES (?, ?, ?, ?, ?, ?, (SELECT COALESCE(MAX(number), 0) + 1 FROM sessions))
            """,
            [
                .text(session.id),
                .text(session.title),
                session.providerId.map(SQLiteValue.text) ?? .null,
                session.model.map(SQLiteValue.text) ?? .null,
                DateCoding.value(session.createdAt),
                DateCoding.value(session.updatedAt),
            ]
        )
        session.number = try database.query(
            "SELECT number FROM sessions WHERE id = ?",
            [.text(session.id)]
        ).first?.int("number").map(Int.init) ?? 0
        return session
    }

    public func sessions() throws -> [Session] {
        try database.query("SELECT * FROM sessions ORDER BY updated_at DESC").compactMap(decodeSession)
    }

    public func renameSession(id: String, title: String) throws {
        try database.run(
            "UPDATE sessions SET title = ?, updated_at = ? WHERE id = ?",
            [.text(title), DateCoding.value(Date()), .text(id)]
        )
    }

    public func deleteSession(id: String) throws {
        try database.run("DELETE FROM sessions WHERE id = ?", [.text(id)])
    }

    public func touchSession(id: String) throws {
        try database.run(
            "UPDATE sessions SET updated_at = ? WHERE id = ?",
            [DateCoding.value(Date()), .text(id)]
        )
    }

    public func appendMessage(_ message: ChatMessage) throws {
        try database.run(
            """
            INSERT INTO messages(id, session_id, role, content, tool_call_id, tool_calls_json, name, attachments_json, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(message.id),
                .text(message.sessionId),
                .text(message.role.rawValue),
                .text(message.content),
                message.toolCallId.map(SQLiteValue.text) ?? .null,
                toolCallsJSON(message.toolCalls).map(SQLiteValue.text) ?? .null,
                message.name.map(SQLiteValue.text) ?? .null,
                attachmentsJSON(message.attachments).map(SQLiteValue.text) ?? .null,
                DateCoding.value(message.createdAt),
            ]
        )
        try touchSession(id: message.sessionId)
    }

    public func messages(sessionId: String) throws -> [ChatMessage] {
        try database.query(
            "SELECT * FROM messages WHERE session_id = ? ORDER BY created_at ASC, rowid ASC",
            [.text(sessionId)]
        ).compactMap(decodeMessage)
    }

    /// Adds token usage to a session and returns the updated running total.
    @discardableResult
    public func recordUsage(
        sessionId: String,
        promptTokens: Int,
        completionTokens: Int,
        costUSD: Double
    ) throws -> SessionUsage {
        try database.run(
            """
            UPDATE sessions
            SET prompt_tokens = prompt_tokens + ?,
                completion_tokens = completion_tokens + ?,
                cost_usd = cost_usd + ?
            WHERE id = ?
            """,
            [
                .integer(Int64(promptTokens)),
                .integer(Int64(completionTokens)),
                .real(costUSD),
                .text(sessionId),
            ]
        )
        try touchSession(id: sessionId)
        return try usage(sessionId: sessionId)
    }

    /// One-time repair for sessions recorded before a model had a price
    /// entry: estimate the historical cost from the stored token totals.
    /// Cache hit/miss data is not available for old turns, so the cache-miss
    /// rate is used and the session creation time selects the peak rate.
    public func backfillMissingCosts() throws {
        let rows = try database.query(
            """
            SELECT id, model, prompt_tokens, completion_tokens, created_at
            FROM sessions
            WHERE cost_usd = 0 AND (prompt_tokens > 0 OR completion_tokens > 0)
            """
        )
        for row in rows {
            guard
                let id = row.string("id"),
                let model = row.string("model"),
                !model.isEmpty,
                let createdAt = DateCoding.date(row["created_at"])
            else { continue }
            let prompt = Int(row.int("prompt_tokens") ?? 0)
            let completion = Int(row.int("completion_tokens") ?? 0)
            guard let cost = Pricing.cost(
                model: model,
                promptTokens: prompt,
                completionTokens: completion,
                at: createdAt
            ), cost > 0 else { continue }
            try database.run(
                "UPDATE sessions SET cost_usd = ? WHERE id = ?",
                [.real(cost), .text(id)]
            )
        }
    }

    public func usage(sessionId: String) throws -> SessionUsage {
        let rows = try database.query(
            "SELECT prompt_tokens, completion_tokens, cost_usd FROM sessions WHERE id = ?",
            [.text(sessionId)]
        )
        guard let row = rows.first else { return .zero }
        return SessionUsage(
            promptTokens: Int(row.int("prompt_tokens") ?? 0),
            completionTokens: Int(row.int("completion_tokens") ?? 0),
            costUSD: row.double("cost_usd") ?? 0
        )
    }

    public func recordToolCall(_ call: ToolCallRecord) throws {
        try database.run(
            """
            INSERT INTO tool_calls(id, session_id, session_number, module_id, tool_name, arguments_json, result_json, status, started_at, finished_at)
            VALUES (?, ?, (SELECT number FROM sessions WHERE id = ?), ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                result_json = excluded.result_json,
                status = excluded.status,
                finished_at = excluded.finished_at,
                session_number = excluded.session_number
            """,
            [
                .text(call.id),
                .text(call.sessionId),
                .text(call.sessionId),
                .text(call.moduleId),
                .text(call.toolName),
                .text(call.argumentsJSON),
                call.resultJSON.map(SQLiteValue.text) ?? .null,
                .text(call.status.rawValue),
                DateCoding.value(call.startedAt),
                DateCoding.optional(call.finishedAt),
            ]
        )
    }

    public func toolCalls(sessionId: String, limit: Int = 200) throws -> [ToolCallRecord] {
        try database.query(
            """
            SELECT * FROM (
                SELECT * FROM tool_calls WHERE session_id = ? ORDER BY started_at DESC LIMIT ?
            ) ORDER BY started_at ASC
            """,
            [.text(sessionId), .integer(Int64(limit))]
        ).compactMap(decodeToolCall)
    }

    public func toolCalls(limit: Int = 200) throws -> [ToolCallRecord] {
        try database.query(
            "SELECT * FROM tool_calls ORDER BY started_at DESC LIMIT ?",
            [.integer(Int64(limit))]
        ).compactMap(decodeToolCall)
    }

    public func toolCallCount(sessionId: String) throws -> Int {
        try database.query(
            "SELECT COUNT(*) AS total FROM tool_calls WHERE session_id = ?",
            [.text(sessionId)]
        ).first?.int("total").map(Int.init) ?? 0
    }

    private func decodeSession(_ row: Row) -> Session? {
        guard
            let id = row.string("id"),
            let title = row.string("title"),
            let createdAt = DateCoding.date(row["created_at"]),
            let updatedAt = DateCoding.date(row["updated_at"])
        else { return nil }
        return Session(
            id: id,
            number: Int(row.int("number") ?? 0),
            title: title,
            providerId: row.string("provider_id"),
            model: row.string("model"),
            createdAt: createdAt,
            updatedAt: updatedAt,
            promptTokens: Int(row.int("prompt_tokens") ?? 0),
            completionTokens: Int(row.int("completion_tokens") ?? 0),
            costUSD: row.double("cost_usd") ?? 0
        )
    }

    private func decodeMessage(_ row: Row) -> ChatMessage? {
        guard
            let id = row.string("id"),
            let sessionId = row.string("session_id"),
            let roleRaw = row.string("role"),
            let role = MessageRole(rawValue: roleRaw),
            let content = row.string("content"),
            let createdAt = DateCoding.date(row["created_at"])
        else { return nil }
        return ChatMessage(
            id: id,
            sessionId: sessionId,
            role: role,
            content: content,
            toolCallId: row.string("tool_call_id"),
            toolCalls: toolCalls(row.string("tool_calls_json")),
            name: row.string("name"),
            attachments: attachments(row.string("attachments_json")),
            createdAt: createdAt
        )
    }

    private func toolCallsJSON(_ calls: [LLMToolCall]) -> String? {
        guard !calls.isEmpty, let data = try? encoder.encode(calls) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func toolCalls(_ json: String?) -> [LLMToolCall] {
        guard
            let json,
            let data = json.data(using: .utf8),
            let decoded = try? decoder.decode([LLMToolCall].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func attachmentsJSON(_ attachments: [ChatAttachment]) -> String? {
        guard !attachments.isEmpty, let data = try? encoder.encode(attachments) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func attachments(_ json: String?) -> [ChatAttachment] {
        guard
            let json,
            let data = json.data(using: .utf8),
            let decoded = try? decoder.decode([ChatAttachment].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func decodeToolCall(_ row: Row) -> ToolCallRecord? {
        guard
            let id = row.string("id"),
            let sessionId = row.string("session_id"),
            let moduleId = row.string("module_id"),
            let toolName = row.string("tool_name"),
            let argumentsJSON = row.string("arguments_json"),
            let statusRaw = row.string("status"),
            let status = ToolCallStatus(rawValue: statusRaw),
            let startedAt = DateCoding.date(row["started_at"])
        else { return nil }
        return ToolCallRecord(
            id: id,
            sessionId: sessionId,
            sessionNumber: row.int("session_number").map(Int.init),
            moduleId: moduleId,
            toolName: toolName,
            argumentsJSON: argumentsJSON,
            resultJSON: row.string("result_json"),
            status: status,
            startedAt: startedAt,
            finishedAt: DateCoding.date(row["finished_at"])
        )
    }
}
