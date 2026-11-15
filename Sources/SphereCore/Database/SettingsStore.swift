import Foundation

public final class SettingsStore {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func string(_ key: String) throws -> String? {
        try database.query("SELECT value FROM settings WHERE key = ?", [.text(key)]).first?.string("value")
    }

    public func set(_ key: String, value: String) throws {
        try database.run(
            "INSERT INTO settings(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            [.text(key), .text(value)]
        )
    }

    public func remove(_ key: String) throws {
        try database.run("DELETE FROM settings WHERE key = ?", [.text(key)])
    }
}
