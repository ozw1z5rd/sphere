import Foundation
import AppKit

/// Canonical, per-user locations for all Sphere data.
///
/// Everything lives under `~/Library/Application Support/Sphere/` so the app
/// requires no administrator privileges and keeps user data isolated.
public enum AppPaths {
    public static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Sphere", isDirectory: true)
    }

    public static var database: URL {
        applicationSupport.appendingPathComponent("sphere.sqlite")
    }

    public static var config: URL {
        applicationSupport.appendingPathComponent("config.json")
    }

    public static var plugins: URL {
        applicationSupport.appendingPathComponent("Plugins", isDirectory: true)
    }

    public static var store: URL {
        applicationSupport.appendingPathComponent("Store", isDirectory: true)
    }

    public static var captures: URL {
        applicationSupport.appendingPathComponent("Captures", isDirectory: true)
    }

    public static var logs: URL {
        applicationSupport.appendingPathComponent("Logs", isDirectory: true)
    }

    /// Creates the directory tree if needed. Safe to call repeatedly.
    public static func ensureDirectories() throws {
        for url in [applicationSupport, plugins, store, captures, logs] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Opens the plugins folder in Finder.
    public static func revealPluginsFolder() throws {
        try ensureDirectories()
        NSWorkspace.shared.open(plugins)
    }
}
