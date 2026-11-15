import Foundation
import SphereCore
import SphereLLM
import SphereMCP
import SphereTools
import SphereScreen
import SphereKnowledge

/// Wires every subsystem together. Shared by the SwiftUI app and the CLI so
/// both use exactly the same storage, permissions and tool routing.
public final class SphereRuntime: @unchecked Sendable {
    public let database: Database
    public let configStore: ConfigStore
    public private(set) var config: AppConfig

    public let sessions: SessionStore
    public let modules: ModuleRegistry
    public let permissions: PermissionStore
    public let settings: SettingsStore
    public let audit: AuditLog
    public let engine: PermissionEngine
    public let broker: FilesystemBroker
    public let networkStore: NetworkStore
    public let networkPolicy: NetworkPolicy
    public let web: WebToolProvider
    public let git: GitToolProvider
    public let system: SystemToolProvider
    public let exec: ExecToolProvider
    public let host: MCPModuleHost
    public let router: ToolRouter
    public let screen: ScreenCaptureService
    public let allowlist: ScreenAllowlist
    public let knowledge: KnowledgeProvider
    public let installer: ModuleInstaller

    public init(databasePath: String? = nil, configURL: URL? = nil) throws {
        try AppPaths.ensureDirectories()

        database = try Database(path: databasePath ?? AppPaths.database.path)
        try Migrations.migrate(database)

        configStore = ConfigStore(url: configURL ?? AppPaths.config)
        config = try configStore.load()

        sessions = SessionStore(database: database)
        modules = ModuleRegistry(database: database)
        permissions = PermissionStore(database: database)
        settings = SettingsStore(database: database)
        audit = AuditLog()

        engine = PermissionEngine(store: permissions)
        broker = FilesystemBroker(engine: engine, audit: audit)
        networkStore = NetworkStore(database: database)
        networkPolicy = NetworkPolicy(store: networkStore)
        web = WebToolProvider(policy: networkPolicy, store: networkStore, audit: audit)
        git = GitToolProvider(engine: engine, audit: audit)
        system = SystemToolProvider(permissions: permissions, audit: audit)
        exec = ExecToolProvider(
            engine: engine,
            audit: audit,
            enabled: config.execEnabled,
            allowlist: config.execAllowlist.isEmpty ? ExecToolProvider.defaultAllowlist : config.execAllowlist
        )
        host = MCPModuleHost()
        router = ToolRouter(host: host, providers: [broker, web, git, system, exec], policy: config.toolPolicy)

        screen = ScreenCaptureService(audit: audit)
        allowlist = ScreenAllowlist(store: permissions)
        knowledge = InMemoryKnowledgeProvider()
        installer = ModuleInstaller(registry: modules)
    }

    // MARK: - Config

    public func saveConfig(_ updated: AppConfig) throws {
        try configStore.save(updated)
        config = updated
        exec.update(
            enabled: updated.execEnabled,
            allowlist: updated.execAllowlist.isEmpty ? ExecToolProvider.defaultAllowlist : updated.execAllowlist
        )
    }

    public func applyPolicy() async {
        await router.setPolicy(config.toolPolicy)
    }

    public var activeProviderConfig: ProviderConfig? {
        guard let id = config.activeProviderId else { return config.providers.first }
        return config.providers.first(where: { $0.id == id }) ?? config.providers.first
    }

    public func apiKey(for provider: ProviderConfig) -> String? {
        SecretStore.get(provider.id)
    }

    public func saveAPIKey(_ key: String, for provider: ProviderConfig) throws {
        try SecretStore.set(key, account: provider.id)
        SphereLog.app.write("provider", "saved API key for \(provider.name)")
    }

    public func deleteAPIKey(for provider: ProviderConfig) {
        SecretStore.delete(account: provider.id)
    }

    /// One-time import of API keys that were stored in the Keychain before the
    /// switch to the file-backed secret store.
    @discardableResult
    public func importKeysFromKeychain() -> Int {
        var imported = 0
        for provider in config.providers {
            let lookup = Keychain.lookup(account: provider.id, allowUI: true)
            guard let value = lookup.value, !value.isEmpty else { continue }
            do {
                try SecretStore.set(value, account: provider.id)
                imported += 1
            } catch {
                SphereLog.app.write(
                    "provider",
                    "import from Keychain failed for \(provider.name): \(error.localizedDescription)"
                )
            }
        }
        return imported
    }

    public func provider(for providerConfig: ProviderConfig) -> LLMProvider? {
        let key = apiKey(for: providerConfig)
        SphereLog.app.write(
            "provider",
            "create \(providerConfig.name) kind=\(providerConfig.kind.rawValue) base=\(providerConfig.baseURL) model=\(providerConfig.model) key=\(key?.isEmpty == false ? "present" : "missing")"
        )
        return LLMProviderFactory.make(
            config: providerConfig,
            apiKey: key,
            debugLogging: config.debugHTTPLogging
        )
    }

    public func listModels(for providerConfig: ProviderConfig) async throws -> [LLMModel] {
        guard let provider = provider(for: providerConfig) else {
            throw SphereError.notConfigured("provider '\(providerConfig.name)' is not available")
        }
        return try await provider.listModels()
    }

    public func makeRunner(provider: LLMProvider) -> AgentRunner {
        AgentRunner(provider: provider, router: router, sessions: sessions)
    }

    // MARK: - Modules

    @discardableResult
    public func installModule(from url: URL) throws -> InstalledModule {
        let installed = try installer.install(from: url)
        audit.write("modules", "installed \(installed.id) \(installed.manifest.version)")
        return installed
    }

    public func setModuleEnabled(_ module: InstalledModule, enabled: Bool) async throws {
        if enabled {
            _ = try await host.start(module: module)
            try modules.setEnabled(id: module.id, enabled: true)
            try modules.markStarted(id: module.id)
            audit.write("modules", "enabled \(module.id)")
        } else {
            await host.stop(moduleId: module.id)
            try modules.setEnabled(id: module.id, enabled: false)
            audit.write("modules", "disabled \(module.id)")
        }
    }

    public func startEnabledModules() async {
        let enabled: [InstalledModule]
        do {
            enabled = try modules.enabledModules()
        } catch {
            audit.write("modules", "could not load enabled modules: \(error.localizedDescription)")
            return
        }
        for module in enabled {
            do {
                _ = try await host.start(module: module)
                audit.write("modules", "started \(module.id) on boot")
            } catch {
                audit.write("modules", "failed to start \(module.id): \(error.localizedDescription)")
            }
        }
    }

    public func stopAllModules() async {
        await host.stopAll()
    }

    // MARK: - Defaults

    public static let defaultSystemPrompt = """
    You are Sphere, a local AI assistant running natively on macOS.

    You can use tools exposed by installed modules:
    - File access goes through the Sphere filesystem broker and is limited to the
      paths the user explicitly granted. Read-only grants cannot be written.
    - Screenshots are only possible for windows the user explicitly allowed.
    - Internet access uses the web_fetch tool; the user's URL/domain/IP ban list
      is enforced and must not be bypassed.
    - Always ask for the minimum access you need and explain why.

    When you call a tool, wait for its result before answering. Be concise.
    """
}
