import Foundation

public enum Migrations {
    public struct Migration {
        public let version: Int
        public let sql: String

        public init(version: Int, sql: String) {
            self.version = version
            self.sql = sql
        }
    }

    public static let all: [Migration] = [
        Migration(version: 1, sql: """
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            applied_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            provider_id TEXT,
            model TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            tool_call_id TEXT,
            name TEXT,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id, created_at);

        CREATE TABLE IF NOT EXISTS tool_calls (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            module_id TEXT NOT NULL,
            tool_name TEXT NOT NULL,
            arguments_json TEXT NOT NULL,
            result_json TEXT,
            status TEXT NOT NULL,
            started_at REAL NOT NULL,
            finished_at REAL
        );
        CREATE INDEX IF NOT EXISTS idx_tool_calls_session ON tool_calls(session_id, started_at);

        CREATE TABLE IF NOT EXISTS modules (
            id TEXT PRIMARY KEY,
            manifest_json TEXT NOT NULL,
            install_path TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 0,
            installed_at REAL NOT NULL,
            last_started_at REAL
        );

        CREATE TABLE IF NOT EXISTS path_grants (
            id TEXT PRIMARY KEY,
            path TEXT NOT NULL,
            mode TEXT NOT NULL,
            recursive INTEGER NOT NULL DEFAULT 1,
            scope TEXT NOT NULL,
            module_id TEXT,
            created_at REAL NOT NULL,
            last_used_at REAL,
            read_count INTEGER NOT NULL DEFAULT 0,
            write_count INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_path_grants_path ON path_grants(path);

        CREATE TABLE IF NOT EXISTS access_events (
            id TEXT PRIMARY KEY,
            grant_id TEXT,
            module_id TEXT NOT NULL,
            path TEXT NOT NULL,
            operation TEXT NOT NULL,
            allowed INTEGER NOT NULL,
            detail TEXT,
            timestamp REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_access_events_time ON access_events(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_access_events_path ON access_events(path);

        CREATE TABLE IF NOT EXISTS screen_grants (
            id TEXT PRIMARY KEY,
            bundle_id TEXT,
            app_name TEXT NOT NULL,
            window_title TEXT,
            window_id INTEGER,
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL,
            last_used_at REAL,
            capture_count INTEGER NOT NULL DEFAULT 0
        );
        """),
        Migration(version: 2, sql: """
        ALTER TABLE sessions ADD COLUMN prompt_tokens INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE sessions ADD COLUMN completion_tokens INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE sessions ADD COLUMN cost_usd REAL NOT NULL DEFAULT 0;
        """),
        Migration(version: 3, sql: """
        ALTER TABLE messages ADD COLUMN attachments_json TEXT;
        """),
        Migration(version: 4, sql: """
        CREATE TABLE IF NOT EXISTS network_rules (
            id TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            kind TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            reason TEXT,
            created_at REAL NOT NULL,
            last_blocked_at REAL,
            blocked_count INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_network_rules_value ON network_rules(value);

        CREATE TABLE IF NOT EXISTS network_events (
            id TEXT PRIMARY KEY,
            url TEXT NOT NULL,
            host TEXT NOT NULL,
            allowed INTEGER NOT NULL,
            rule_id TEXT,
            detail TEXT,
            timestamp REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_network_events_time ON network_events(timestamp DESC);
        """),
        Migration(version: 5, sql: """
        ALTER TABLE messages ADD COLUMN tool_calls_json TEXT;
        """),
        Migration(version: 6, sql: """
        CREATE TABLE IF NOT EXISTS clipboard_events (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            operation TEXT NOT NULL,
            detail TEXT,
            allowed INTEGER NOT NULL DEFAULT 1,
            timestamp REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_clipboard_events_time ON clipboard_events(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_clipboard_events_session ON clipboard_events(session_id, timestamp DESC);
        """),
        Migration(version: 7, sql: """
        ALTER TABLE sessions ADD COLUMN number INTEGER NOT NULL DEFAULT 0;
        UPDATE sessions SET number = (
            SELECT COUNT(*) FROM sessions AS older
            WHERE older.created_at < sessions.created_at
               OR (older.created_at = sessions.created_at AND older.rowid <= sessions.rowid)
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_number ON sessions(number);

        ALTER TABLE access_events ADD COLUMN session_id TEXT;
        ALTER TABLE access_events ADD COLUMN session_number INTEGER;
        ALTER TABLE network_events ADD COLUMN session_id TEXT;
        ALTER TABLE network_events ADD COLUMN session_number INTEGER;
        ALTER TABLE clipboard_events ADD COLUMN session_number INTEGER;
        ALTER TABLE tool_calls ADD COLUMN session_number INTEGER;

        UPDATE clipboard_events SET session_number = (
            SELECT number FROM sessions WHERE sessions.id = clipboard_events.session_id
        ) WHERE session_id IS NOT NULL;
        UPDATE tool_calls SET session_number = (
            SELECT number FROM sessions WHERE sessions.id = tool_calls.session_id
        );

        CREATE INDEX IF NOT EXISTS idx_access_events_session ON access_events(session_id, timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_network_events_session ON network_events(session_id, timestamp DESC);
        """),
    ]

    public static func migrate(_ database: Database) throws {
        try database.executeScript("""
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            applied_at REAL NOT NULL
        );
        """)

        let applied = Set(try database.query("SELECT version FROM schema_migrations").compactMap { $0.int("version").map(Int.init) })

        for migration in all where !applied.contains(migration.version) {
            try database.executeScript(migration.sql)
            try database.run(
                "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                [.integer(Int64(migration.version)), .real(Date().timeIntervalSince1970)]
            )
        }
    }
}

public enum DateCoding {
    public static func value(_ date: Date) -> SQLiteValue {
        .real(date.timeIntervalSince1970)
    }

    public static func optional(_ date: Date?) -> SQLiteValue {
        guard let date else { return .null }
        return .real(date.timeIntervalSince1970)
    }

    public static func date(_ value: SQLiteValue?) -> Date? {
        value?.doubleValue.map(Date.init(timeIntervalSince1970:))
    }
}
