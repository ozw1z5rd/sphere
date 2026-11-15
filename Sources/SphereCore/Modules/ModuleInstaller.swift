import Foundation
import CryptoKit

public enum ModulePackageType: String, Sendable {
    case spheremodule
    case sphereplug
    case zip
    case directory

    public static func infer(from url: URL) -> ModulePackageType? {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if isDirectory.boolValue { return .directory }
        switch url.pathExtension.lowercased() {
        case "spheremodule": return .spheremodule
        case "sphereplug": return .sphereplug
        case "zip": return .zip
        default: return nil
        }
    }
}

/// Installs `.spheremodule` / `.sphereplug` / `.zip` / folder packages into the
/// per-user Plugins directory. End users never author or edit the manifest.
public final class ModuleInstaller {
    private let registry: ModuleRegistry
    private let pluginsDirectory: URL
    private let storeDirectory: URL

    public init(
        registry: ModuleRegistry,
        pluginsDirectory: URL = AppPaths.plugins,
        storeDirectory: URL = AppPaths.store
    ) {
        self.registry = registry
        self.pluginsDirectory = pluginsDirectory
        self.storeDirectory = storeDirectory
    }

    @discardableResult
    public func install(from url: URL) throws -> InstalledModule {
        try AppPaths.ensureDirectories()
        guard let type = ModulePackageType.infer(from: url) else {
            throw SphereError.invalidManifest("unsupported file type '\(url.pathExtension)'")
        }

        switch type {
        case .spheremodule, .zip:
            return try installArchive(url)
        case .sphereplug:
            return try installSingleScript(url)
        case .directory:
            return try installDirectory(url)
        }
    }

    // MARK: - Archive

    private func installArchive(_ url: URL) throws -> InstalledModule {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("sphere-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        try runDitto(arguments: ["-x", "-k", url.path, staging.path])
        guard let manifestURL = findManifest(in: staging) else {
            throw SphereError.invalidManifest("module.json not found inside archive")
        }
        let manifest = try loadManifest(at: manifestURL)
        try manifest.validate()

        let sourceRoot = manifestURL.deletingLastPathComponent()
        let destination = try installDirectoryContents(from: sourceRoot, manifest: manifest)
        try archiveOriginal(url, manifest: manifest)
        return destination
    }

    // MARK: - Single script

    private func installSingleScript(_ url: URL) throws -> InstalledModule {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SphereError.invalidManifest("script is not valid UTF-8")
        }
        var manifest = try ScriptManifestParser.parse(text)
        let destination = pluginsDirectory.appendingPathComponent(manifest.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let scriptName = url.lastPathComponent
        let scriptURL = destination.appendingPathComponent(scriptName)
        try FileManager.default.copyItem(at: url, to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        if manifest.transport == nil {
            manifest.transport = ModuleTransport(command: ["${MODULE_DIR}/\(scriptName)"])
        }
        try manifest.validate()

        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: destination.appendingPathComponent("module.json"), options: .atomic)

        let installed = InstalledModule(manifest: manifest, installPath: destination.path, enabled: false)
        try registry.upsert(installed)
        try archiveOriginal(url, manifest: manifest)
        return installed
    }

    // MARK: - Directory

    private func installDirectory(_ url: URL) throws -> InstalledModule {
        guard let manifestURL = findManifest(in: url) else {
            throw SphereError.invalidManifest("module.json not found in folder")
        }
        let manifest = try loadManifest(at: manifestURL)
        try manifest.validate()
        let contents = manifestURL.deletingLastPathComponent()
        return try installDirectoryContents(from: contents, manifest: manifest)
    }

    // MARK: - Helpers

    private func installDirectoryContents(from source: URL, manifest: ModuleManifest) throws -> InstalledModule {
        let destination = pluginsDirectory.appendingPathComponent(manifest.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        for item in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            try FileManager.default.copyItem(at: item, to: target)
        }

        let installed = InstalledModule(manifest: manifest, installPath: destination.path, enabled: false)
        try registry.upsert(installed)
        return installed
    }

    private func archiveOriginal(_ url: URL, manifest: ModuleManifest) throws {
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let archived = storeDirectory.appendingPathComponent("\(manifest.id)-\(manifest.version).\(url.pathExtension)")
        if FileManager.default.fileExists(atPath: archived.path) {
            try FileManager.default.removeItem(at: archived)
        }
        try FileManager.default.copyItem(at: url, to: archived)
    }

    private func loadManifest(at url: URL) throws -> ModuleManifest {
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(ModuleManifest.self, from: data)
        } catch {
            throw SphereError.invalidManifest("could not decode module.json: \(error)")
        }
    }

    private func findManifest(in directory: URL) -> URL? {
        let direct = directory.appendingPathComponent("module.json")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }

        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var depthGuard = 0
        while let candidate = enumerator?.nextObject() as? URL {
            if candidate.lastPathComponent == "module.json" {
                return candidate
            }
            depthGuard += 1
            if depthGuard > 2_000 { break }
        }
        return nil
    }

    private func runDitto(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "unknown error"
            throw SphereError.archiveExtractionFailed(message)
        }
    }

    private func sha256(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Parses the metadata header embedded in a `.sphereplug` script.
enum ScriptManifestParser {
    static let beginMarker = "--- sphere-module ---"
    static let endMarker = "--- end sphere-module ---"

    static func parse(_ text: String) throws -> ModuleManifest {
        let lines = text.components(separatedBy: .newlines)
        guard let begin = lines.firstIndex(where: { $0.contains(beginMarker) }) else {
            throw SphereError.invalidManifest("missing \(beginMarker) header")
        }
        guard let end = lines[begin...].firstIndex(where: { $0.contains(endMarker) }) else {
            throw SphereError.invalidManifest("missing \(endMarker) marker")
        }

        let body = lines[(begin + 1)..<end]
            .map { line -> String in
                var trimmed = line.trimmingCharacters(in: .whitespaces)
                while trimmed.hasPrefix("#") {
                    trimmed.removeFirst()
                    trimmed = trimmed.trimmingCharacters(in: .whitespaces)
                }
                return trimmed
            }
            .filter { !$0.isEmpty }

        let joined = body.joined(separator: "\n")
        if joined.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
            guard let data = joined.data(using: .utf8) else {
                throw SphereError.invalidManifest("header is not valid UTF-8")
            }
            return try JSONDecoder().decode(ModuleManifest.self, from: data)
        }

        var fields: [String: String] = [:]
        for line in body {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }

        guard let id = fields["id"], let name = fields["name"], let version = fields["version"] else {
            throw SphereError.invalidManifest("header requires id, name and version")
        }
        return ModuleManifest(
            id: id,
            name: name,
            version: version,
            author: fields["author"],
            description: fields["description"],
            kind: ModuleKind(rawValue: fields["kind"] ?? "mcp") ?? .mcp,
            transport: nil
        )
    }
}
