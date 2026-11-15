import Foundation

/// Process-wide loggers. Each category writes to its own file under
/// `~/Library/Application Support/Sphere/Logs/`.
public enum SphereLog {
    public static let app = AuditLog()
    public static let http = AuditLog(fileURL: AppPaths.logs.appendingPathComponent("http.log"))
    public static let keychain = AuditLog(fileURL: AppPaths.logs.appendingPathComponent("keychain.log"))
}
