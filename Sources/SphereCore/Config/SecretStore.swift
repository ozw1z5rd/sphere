import Foundation

/// File-backed secret storage with restrictive permissions.
///
/// The macOS Keychain is tied to the app's code signature; with ad-hoc signing
/// the identity changes on every rebuild and Keychain reads start failing with
/// errSecUserCanceled. To keep API keys usable across rebuilds, Sphere stores
/// them in `secrets.json` (0600) and only uses the Keychain for one-time import.
public enum SecretStore {
    public static var fileURL: URL {
        AppPaths.applicationSupport.appendingPathComponent("secrets.json")
    }

    private static let lock = NSLock()

    public static func get(_ account: String) -> String? {
        lock.lock()
        let secrets = loadLocked()
        lock.unlock()

        if let value = secrets[account], !value.isEmpty {
            return value
        }

        let lookup = Keychain.lookup(account: account, allowUI: false)
        if let value = lookup.value, !value.isEmpty {
            try? set(value, account: account)
            SphereLog.keychain.write(
                "secrets",
                "migrated Keychain item account=\(account) to secrets file"
            )
            return value
        }
        return nil
    }

    public static func set(_ value: String, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var secrets = loadLocked()
        secrets[account] = value
        try saveLocked(secrets)
        SphereLog.keychain.write("secrets", "set account=\(account) length=\(value.count)")
    }

    public static func delete(account: String) {
        lock.lock()
        defer { lock.unlock() }
        var secrets = loadLocked()
        secrets[account] = nil
        try? saveLocked(secrets)
        SphereLog.keychain.write("secrets", "delete account=\(account)")
    }

    public static func accounts() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(loadLocked().keys).sorted()
    }

    private static func loadLocked() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func saveLocked(_ secrets: [String: String]) throws {
        try AppPaths.ensureDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(secrets)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
