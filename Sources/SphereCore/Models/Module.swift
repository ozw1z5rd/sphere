import Foundation

public enum ModuleKind: String, Codable, CaseIterable, Sendable {
    case mcp
    case knowledge
    case tool
}

public enum FileAccessMode: String, Codable, CaseIterable, Sendable {
    case readOnly = "ro"
    case readWrite = "rw"

    public var canWrite: Bool { self == .readWrite }
}

public enum GrantScope: String, Codable, CaseIterable, Sendable {
    case session
    case persistent
}

public struct ModuleHealthCheck: Codable, Sendable {
    public var method: String
    public var timeoutMs: Int

    public init(method: String = "tools/list", timeoutMs: Int = 15_000) {
        self.method = method
        self.timeoutMs = timeoutMs
    }
}

public struct ModuleTransport: Codable, Sendable {
    public var type: String
    public var command: [String]
    public var cwd: String?
    public var env: [String: String]?
    public var healthCheck: ModuleHealthCheck?

    public init(
        type: String = "stdio",
        command: [String],
        cwd: String? = nil,
        env: [String: String]? = nil,
        healthCheck: ModuleHealthCheck? = nil
    ) {
        self.type = type
        self.command = command
        self.cwd = cwd
        self.env = env
        self.healthCheck = healthCheck
    }
}

public struct FilesystemPermission: Codable, Sendable {
    public var paths: [String]
    public var mode: FileAccessMode
    public var reason: String?

    public init(paths: [String], mode: FileAccessMode = .readOnly, reason: String? = nil) {
        self.paths = paths
        self.mode = mode
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case paths, mode, reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.paths = try container.decodeIfPresent([String].self, forKey: .paths) ?? []
        self.mode = try container.decodeIfPresent(FileAccessMode.self, forKey: .mode) ?? .readOnly
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }
}

public struct ScreenPermission: Codable, Sendable {
    public var windows: [String]?
    public var reason: String?

    public init(windows: [String]? = nil, reason: String? = nil) {
        self.windows = windows
        self.reason = reason
    }
}

public struct ModulePermissions: Codable, Sendable {
    public var filesystem: FilesystemPermission?
    public var screen: ScreenPermission?
    public var network: Bool
    public var process: Bool

    public init(
        filesystem: FilesystemPermission? = nil,
        screen: ScreenPermission? = nil,
        network: Bool = false,
        process: Bool = false
    ) {
        self.filesystem = filesystem
        self.screen = screen
        self.network = network
        self.process = process
    }

    private enum CodingKeys: String, CodingKey {
        case filesystem, screen, network, process
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.filesystem = try container.decodeIfPresent(FilesystemPermission.self, forKey: .filesystem)
        self.screen = try container.decodeIfPresent(ScreenPermission.self, forKey: .screen)
        self.network = try container.decodeIfPresent(Bool.self, forKey: .network) ?? false
        self.process = try container.decodeIfPresent(Bool.self, forKey: .process) ?? false
    }
}

public struct ModuleSetting: Codable, Sendable, Identifiable {
    public enum ValueType: String, Codable, Sendable {
        case string
        case secret
        case boolean
        case integer
    }

    public var key: String
    public var label: String
    public var type: ValueType
    public var required: Bool
    public var defaultValue: String?

    public var id: String { key }

    public init(
        key: String,
        label: String,
        type: ValueType = .string,
        required: Bool = false,
        defaultValue: String? = nil
    ) {
        self.key = key
        self.label = label
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
    }
}

public struct ModuleUI: Codable, Sendable {
    public var category: String?
    public var settings: [ModuleSetting]?

    public init(category: String? = nil, settings: [ModuleSetting]? = nil) {
        self.category = category
        self.settings = settings
    }
}

/// The self-describing manifest authored by the module developer and shipped
/// inside the module file. End users never write this.
public struct ModuleManifest: Codable, Sendable, Identifiable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var version: String
    public var author: String?
    public var description: String?
    public var icon: String?
    public var kind: ModuleKind
    public var transport: ModuleTransport?
    public var capabilities: [String]
    public var permissions: ModulePermissions
    public var ui: ModuleUI?
    public var autoStart: Bool

    public init(
        schemaVersion: Int = ModuleManifest.currentSchemaVersion,
        id: String,
        name: String,
        version: String,
        author: String? = nil,
        description: String? = nil,
        icon: String? = nil,
        kind: ModuleKind = .mcp,
        transport: ModuleTransport? = nil,
        capabilities: [String] = ["tools"],
        permissions: ModulePermissions = ModulePermissions(),
        ui: ModuleUI? = nil,
        autoStart: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.icon = icon
        self.kind = kind
        self.transport = transport
        self.capabilities = capabilities
        self.permissions = permissions
        self.ui = ui
        self.autoStart = autoStart
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, version, author, description, icon
        case kind, transport, capabilities, permissions, ui, autoStart
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.version = try container.decode(String.self, forKey: .version)
        self.author = try container.decodeIfPresent(String.self, forKey: .author)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon)
        self.kind = try container.decodeIfPresent(ModuleKind.self, forKey: .kind) ?? .mcp
        self.transport = try container.decodeIfPresent(ModuleTransport.self, forKey: .transport)
        self.capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? ["tools"]
        self.permissions = try container.decodeIfPresent(ModulePermissions.self, forKey: .permissions) ?? ModulePermissions()
        self.ui = try container.decodeIfPresent(ModuleUI.self, forKey: .ui)
        self.autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
    }

    public func validate() throws {
        guard schemaVersion == ModuleManifest.currentSchemaVersion else {
            throw SphereError.unsupportedManifestVersion(schemaVersion)
        }
        guard !id.isEmpty, id.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw SphereError.invalidManifest("id must match [A-Za-z0-9._-]+")
        }
        guard !name.isEmpty else {
            throw SphereError.invalidManifest("name is empty")
        }
        guard !version.isEmpty else {
            throw SphereError.invalidManifest("version is empty")
        }
        if kind == .mcp || kind == .tool {
            guard let transport, !transport.command.isEmpty else {
                throw SphereError.invalidManifest("transport.command is required for kind '\(kind.rawValue)'")
            }
            guard transport.type == "stdio" else {
                throw SphereError.invalidManifest("only stdio transport is supported (got '\(transport.type)')")
            }
        }
    }
}

/// A manifest together with its on-disk installation state.
public struct InstalledModule: Codable, Sendable, Identifiable {
    public var manifest: ModuleManifest
    public var installPath: String
    public var enabled: Bool
    public var installedAt: Date
    public var lastStartedAt: Date?

    public var id: String { manifest.id }

    public init(
        manifest: ModuleManifest,
        installPath: String,
        enabled: Bool = false,
        installedAt: Date = Date(),
        lastStartedAt: Date? = nil
    ) {
        self.manifest = manifest
        self.installPath = installPath
        self.enabled = enabled
        self.installedAt = installedAt
        self.lastStartedAt = lastStartedAt
    }
}
