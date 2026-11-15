import Foundation
import os

/// Appends human-readable audit lines to `~/Library/Application Support/Sphere/Logs/sphere.log`
/// and mirrors them to the macOS unified log (visible in Console.app).
public final class AuditLog: @unchecked Sendable {
    private static let systemLogger = Logger(subsystem: "com.sphere.app", category: "audit")
    private let queue = DispatchQueue(label: "com.sphere.audit")
    private let fileURL: URL

    public init(fileURL: URL = AppPaths.logs.appendingPathComponent("sphere.log")) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    public func write(_ category: String, _ message: String) {
        Self.systemLogger.info("\(category, privacy: .public): \(message, privacy: .public)")
        let line = "[\(Self.timestamp())] [\(category)] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: self.fileURL, options: .atomic)
            }
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }
}
