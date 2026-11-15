import Foundation

public final class ModuleRegistry {
    private let database: Database
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: Database) {
        self.database = database
    }

    public func all() throws -> [InstalledModule] {
        let rows = try database.query("SELECT * FROM modules ORDER BY id")
        return rows.compactMap(decode)
    }

    public func enabledModules() throws -> [InstalledModule] {
        let rows = try database.query("SELECT * FROM modules WHERE enabled = 1 ORDER BY id")
        return rows.compactMap(decode)
    }

    public func find(id: String) throws -> InstalledModule? {
        let rows = try database.query("SELECT * FROM modules WHERE id = ?", [.text(id)])
        return rows.first.flatMap(decode)
    }

    public func upsert(_ module: InstalledModule) throws {
        let manifestData = try encoder.encode(module.manifest)
        let manifestJSON = String(data: manifestData, encoding: .utf8) ?? "{}"
        try database.run(
            """
            INSERT INTO modules(id, manifest_json, install_path, enabled, installed_at, last_started_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                manifest_json = excluded.manifest_json,
                install_path = excluded.install_path,
                enabled = excluded.enabled,
                installed_at = excluded.installed_at,
                last_started_at = excluded.last_started_at
            """,
            [
                .text(module.id),
                .text(manifestJSON),
                .text(module.installPath),
                .integer(module.enabled ? 1 : 0),
                DateCoding.value(module.installedAt),
                DateCoding.optional(module.lastStartedAt),
            ]
        )
    }

    public func setEnabled(id: String, enabled: Bool) throws {
        try database.run(
            "UPDATE modules SET enabled = ? WHERE id = ?",
            [.integer(enabled ? 1 : 0), .text(id)]
        )
    }

    public func markStarted(id: String) throws {
        try database.run(
            "UPDATE modules SET last_started_at = ? WHERE id = ?",
            [DateCoding.value(Date()), .text(id)]
        )
    }

    public func remove(id: String) throws {
        try database.run("DELETE FROM modules WHERE id = ?", [.text(id)])
    }

    private func decode(_ row: Row) -> InstalledModule? {
        guard
            row.string("id") != nil,
            let manifestJSON = row.string("manifest_json"),
            let manifestData = manifestJSON.data(using: .utf8),
            let manifest = try? decoder.decode(ModuleManifest.self, from: manifestData),
            let installPath = row.string("install_path"),
            let installedAt = DateCoding.date(row["installed_at"])
        else {
            return nil
        }
        return InstalledModule(
            manifest: manifest,
            installPath: installPath,
            enabled: row.bool("enabled") ?? false,
            installedAt: installedAt,
            lastStartedAt: DateCoding.date(row["last_started_at"])
        )
    }
}
