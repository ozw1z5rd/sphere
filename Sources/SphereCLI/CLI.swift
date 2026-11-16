import Foundation
import Darwin
import SphereRuntime
import SphereCore
import SphereLLM
import SphereTools
import SphereScreen

@main
struct SphereCLI {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }

        switch command {
        case "help", "--help", "-h":
            printHelp()

        case "init", "paths":
            let runtime = try SphereRuntime()
            _ = runtime
            print("application support: \(AppPaths.applicationSupport.path)")
            print("database:            \(AppPaths.database.path)")
            print("plugins:             \(AppPaths.plugins.path)")
            print("store:               \(AppPaths.store.path)")

        case "modules":
            try await handleModules(Array(arguments.dropFirst()))

        case "grants", "grant":
            try handleGrants(Array(arguments.dropFirst()))

        case "screens":
            try await handleScreens(Array(arguments.dropFirst()))

        case "key", "keys":
            try handleKeys(Array(arguments.dropFirst()))

        case "say":
            try handleSay(Array(arguments.dropFirst()))

        case "web":
            try await handleWeb(Array(arguments.dropFirst()))

        case "ban", "bans":
            try handleBans(Array(arguments.dropFirst()))

        case "models":
            try await handleModels()

        case "chat":
            try await handleChat(Array(arguments.dropFirst()))

        default:
            print("Unknown command '\(command)'\n")
            printHelp()
        }
    }

    // MARK: - Modules

    static func handleModules(_ arguments: [String]) async throws {
        let runtime = try SphereRuntime()
        let subcommand = arguments.first ?? "list"

        switch subcommand {
        case "list":
            let modules = try runtime.modules.all()
            if modules.isEmpty {
                print("No modules installed.")
                return
            }
            for module in modules {
                let state = module.enabled ? "enabled " : "disabled"
                print("\(state)  \(module.id)  v\(module.manifest.version)  \(module.manifest.name)")
            }

        case "install":
            guard arguments.count >= 2 else {
                throw SphereError.invalidManifest("usage: modules install <path>")
            }
            let url = URL(fileURLWithPath: (arguments[1] as NSString).expandingTildeInPath)
            let module = try runtime.installModule(from: url)
            print("Installed \(module.id) v\(module.manifest.version) at \(module.installPath)")
            print("It is disabled by default. Enable it with: modules enable \(module.id)")

        case "enable":
            guard arguments.count >= 2 else {
                throw SphereError.invalidManifest("usage: modules enable <id>")
            }
            guard let module = try runtime.modules.find(id: arguments[1]) else {
                throw SphereError.moduleNotFound(arguments[1])
            }
            try await runtime.setModuleEnabled(module, enabled: true)
            print("Enabled \(module.id)")

        case "disable":
            guard arguments.count >= 2 else {
                throw SphereError.invalidManifest("usage: modules disable <id>")
            }
            guard let module = try runtime.modules.find(id: arguments[1]) else {
                throw SphereError.moduleNotFound(arguments[1])
            }
            try await runtime.setModuleEnabled(module, enabled: false)
            print("Disabled \(module.id)")

        case "remove":
            guard arguments.count >= 2 else {
                throw SphereError.invalidManifest("usage: modules remove <id>")
            }
            guard let module = try runtime.modules.find(id: arguments[1]) else {
                throw SphereError.moduleNotFound(arguments[1])
            }
            await runtime.host.stop(moduleId: module.id)
            try runtime.modules.remove(id: module.id)
            try? FileManager.default.removeItem(atPath: module.installPath)
            print("Removed \(module.id)")

        case "tools":
            guard arguments.count >= 2 else {
                throw SphereError.invalidManifest("usage: modules tools <id>")
            }
            guard let module = try runtime.modules.find(id: arguments[1]) else {
                throw SphereError.moduleNotFound(arguments[1])
            }
            let tools = try await runtime.host.start(module: module)
            for tool in tools {
                print("\(tool.name): \(tool.description ?? "")")
            }
            await runtime.host.stop(moduleId: module.id)

        default:
            print("usage: modules <list|install|enable|disable|tools>")
        }
    }

    // MARK: - Grants

    static func handleGrants(_ arguments: [String]) throws {
        let runtime = try SphereRuntime()
        let subcommand = arguments.first ?? "list"

        switch subcommand {
        case "list":
            let grants = try runtime.permissions.pathGrants()
            if grants.isEmpty {
                print("No path grants.")
                return
            }
            for grant in grants {
                print("\(grant.mode.rawValue)  read=\(grant.readCount) write=\(grant.writeCount)  \(grant.path)  [\(grant.id)]")
            }

        case "add":
            guard arguments.count >= 2 else {
                throw SphereError.invalidManifest("usage: grant add <path> [ro|rw]")
            }
            let path = PathPolicy.normalize(arguments[1])
            let mode = FileAccessMode(rawValue: arguments.count >= 3 ? arguments[2] : "ro") ?? .readOnly
            let grant = PathGrant(path: path, mode: mode, recursive: true, scope: .persistent)
            try runtime.permissions.addPathGrant(grant)
            print("Granted \(mode.rawValue) on \(path) [\(grant.id)]")

        case "remove":
            guard arguments.count >= 2 else {
                throw SphereError.invalidManifest("usage: grant remove <id>")
            }
            try runtime.permissions.removePathGrant(id: arguments[1])
            print("Removed grant \(arguments[1])")

        case "events":
            let events = try runtime.permissions.accessEvents(limit: 50)
            for event in events {
                let verdict = event.allowed ? "allow" : "deny "
                print("\(verdict) \(event.operation.rawValue) \(event.path) (\(event.moduleId))")
            }

        default:
            print("usage: grant <list|add|remove|events>")
        }
    }

    // MARK: - Screens

    static func handleScreens(_ arguments: [String]) async throws {
        let runtime = try SphereRuntime()
        let subcommand = arguments.first ?? "list"

        switch subcommand {
        case "list":
            let windows = try await runtime.screen.availableWindows()
            for window in windows {
                print("#\(window.id)  \(window.appName)  \(window.title)")
            }

        case "allow":
            guard arguments.count >= 2, let id = UInt32(arguments[1]) else {
                throw SphereError.invalidManifest("usage: screens allow <windowId>")
            }
            let windows = try await runtime.screen.availableWindows()
            guard let window = windows.first(where: { $0.id == id }) else {
                throw SphereError.processFailed("window \(id) not found")
            }
            let grant = try runtime.allowlist.allow(window: window)
            print("Allowed \(window.appName) '\(window.title)' [\(grant.id)]")

        case "capture":
            guard arguments.count >= 2, let id = UInt32(arguments[1]) else {
                throw SphereError.invalidManifest("usage: screens capture <windowId>")
            }
            let windows = try await runtime.screen.availableWindows()
            guard let window = windows.first(where: { $0.id == id }) else {
                throw SphereError.processFailed("window \(id) not found")
            }
            guard try runtime.allowlist.isAllowed(window) else {
                throw SphereError.permissionDenied("window \(id) is not allowed; run screens allow \(id)")
            }
            let data = try await runtime.screen.captureWindow(window)
            let target = AppPaths.captures.appendingPathComponent("capture-\(id)-\(Int(Date().timeIntervalSince1970)).png")
            try FileManager.default.createDirectory(at: AppPaths.captures, withIntermediateDirectories: true)
            try data.write(to: target)
            print(target.path)

        default:
            print("usage: screens <list|allow|capture>")
        }
    }

    // MARK: - Say

    static func handleSay(_ arguments: [String]) throws {
        let text = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw SphereError.notConfigured("usage: say <text>")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = [text]
        try process.run()
        process.waitUntilExit()
    }

    // MARK: - Web and bans

    static func handleWeb(_ arguments: [String]) async throws {
        guard let raw = arguments.first, !raw.isEmpty else {
            throw SphereError.notConfigured("usage: web <url>")
        }
        let runtime = try SphereRuntime()
        let outcome = try await runtime.web.invoke(
            tool: "web_fetch",
            arguments: .object(["url": .string(raw)]),
            sessionId: nil
        )
        print(outcome.text)
    }

    static func handleBans(_ arguments: [String]) throws {
        let runtime = try SphereRuntime()
        let subcommand = arguments.first ?? "list"

        switch subcommand {
        case "list":
            let rules = try runtime.networkStore.rules()
            if rules.isEmpty {
                print("No network bans.")
                return
            }
            for rule in rules {
                let state = rule.enabled ? "on " : "off"
                print("\(state) \(rule.kind.rawValue) \(rule.value) blocked=\(rule.blockedCount) [\(rule.id)]")
            }

        case "add":
            guard arguments.count >= 3,
                  let kind = NetworkRuleKind(rawValue: arguments[1]),
                  let normalized = NetworkPolicy.normalizeRuleValue(arguments[2], kind: kind)
            else {
                throw SphereError.notConfigured("usage: ban add <url|domain|ip> <value>")
            }
            try runtime.networkStore.addRule(NetworkRule(value: normalized, kind: kind))
            print("Banned \(kind.rawValue) \(normalized)")

        case "remove":
            guard arguments.count >= 2 else {
                throw SphereError.notConfigured("usage: ban remove <id>")
            }
            try runtime.networkStore.removeRule(id: arguments[1])
            print("Removed ban \(arguments[1])")

        case "events":
            for event in try runtime.networkStore.events(limit: 50) {
                print("\(event.allowed ? "allow" : "block") \(event.url)")
            }

        default:
            print("usage: ban <list|add|remove|events>")
        }
    }

    // MARK: - Keys

    static func handleKeys(_ arguments: [String]) throws {
        let runtime = try SphereRuntime()
        let subcommand = arguments.first ?? "list"

        switch subcommand {
        case "list":
            let accounts = SecretStore.accounts()
            if accounts.isEmpty {
                print("No secrets stored.")
                return
            }
            for account in accounts {
                let name = runtime.config.providers.first(where: { $0.id == account })?.name ?? "unknown provider"
                print("- \(name) [\(account)]")
            }

        case "set":
            guard arguments.count >= 3 else {
                throw SphereError.notConfigured("usage: key set <providerId|name> <key>")
            }
            guard let provider = findProvider(arguments[1], in: runtime.config) else {
                throw SphereError.notConfigured("provider '\(arguments[1])' not found")
            }
            try runtime.saveAPIKey(arguments[2], for: provider)
            print("Saved API key for \(provider.name)")

        case "delete":
            guard arguments.count >= 2,
                  let provider = findProvider(arguments[1], in: runtime.config) else {
                throw SphereError.notConfigured("usage: key delete <providerId|name>")
            }
            runtime.deleteAPIKey(for: provider)
            print("Deleted API key for \(provider.name)")

        case "import-keychain":
            let imported = runtime.importKeysFromKeychain()
            print("Imported \(imported) keys from Keychain")

        default:
            print("usage: key <list|set|delete|import-keychain>")
        }
    }

    static func findProvider(_ needle: String, in config: AppConfig) -> ProviderConfig? {
        config.providers.first {
            $0.id == needle || $0.name.caseInsensitiveCompare(needle) == .orderedSame
        }
    }

    // MARK: - Models

    static func handleModels() async throws {
        let runtime = try SphereRuntime()
        guard let providerConfig = runtime.activeProviderConfig else {
            throw SphereError.notConfigured("no provider configured")
        }
        if runtime.apiKey(for: providerConfig)?.isEmpty ?? true {
            print("Note: no API key stored for \(providerConfig.name).")
        }
        let models = try await runtime.listModels(for: providerConfig)
        print("Provider: \(providerConfig.name) (\(providerConfig.baseURL))")
        if models.isEmpty {
            print("No models returned. Check the provider/key or set the model manually.")
            return
        }
        for model in models {
            print("- \(model.label)")
        }
    }

    // MARK: - Chat

    static func handleChat(_ arguments: [String]) async throws {
        let prompt = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw SphereError.notConfigured("usage: chat <prompt>")
        }
        let runtime = try SphereRuntime()
        guard let providerConfig = runtime.activeProviderConfig else {
            throw SphereError.notConfigured("no provider configured")
        }
        guard let provider = runtime.provider(for: providerConfig) else {
            throw SphereError.notConfigured("provider '\(providerConfig.name)' is not available")
        }

        let session = try runtime.sessions.createSession(title: String(prompt.prefix(40)))
        let runner = runtime.makeRunner(provider: provider)

        let stream = runner.run(
            sessionId: session.id,
            userText: prompt,
            systemPrompt: SphereRuntime.defaultSystemPrompt,
            model: providerConfig.model,
            options: GenerationOptions(provider: providerConfig)
        )

        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                print(delta, terminator: "")
                fflush(stdout)
            case .toolCallStarted(let call):
                print("\n[tool] \(call.moduleId).\(call.toolName)")
            case .toolCallFinished(let call):
                print("[tool result] \(call.status.rawValue)")
            case .usage:
                break
            case .assistantMessage, .completed:
                break
            }
        }
        print()
    }

    static func printHelp() {
        print("""
        Sphere CLI — local AI assistant

        USAGE:
          sphere-cli init                          Initialize storage and print paths
          sphere-cli modules list                  List installed modules
          sphere-cli modules install <path>        Install a .spheremodule/.sphereplug/.zip/folder
          sphere-cli modules enable <id>           Enable and start a module
          sphere-cli modules disable <id>          Stop and disable a module
          sphere-cli modules remove <id>           Uninstall a module
          sphere-cli modules tools <id>            List tools exposed by a module
          sphere-cli grant list                    List path grants and counters
          sphere-cli grant add <path> [ro|rw]      Grant a folder
          sphere-cli grant remove <id>             Revoke a grant
          sphere-cli grant events                  Show the audit log
          sphere-cli screens list                  List shareable windows
          sphere-cli screens allow <windowId>      Allow a window for capture
          sphere-cli screens capture <windowId>    Capture an allowed window to PNG
          sphere-cli key list                      List stored API keys (no values)
          sphere-cli key set <provider> <key>      Store an API key in secrets.json
          sphere-cli key delete <provider>         Remove an API key
          sphere-cli key import-keychain           Import keys from the macOS Keychain
          sphere-cli say <text>                    Speak text with /usr/bin/say
          sphere-cli web <url>                     Fetch a URL through the web tool
          sphere-cli ban list                      List URL/domain/IP bans
          sphere-cli ban add <url|domain|ip> <v>   Add a ban rule
          sphere-cli ban remove <id>               Remove a ban rule
          sphere-cli ban events                    Show recent network requests
          sphere-cli models                        List models available from the active provider
          sphere-cli chat <prompt>                 One-shot agent run using the active provider
        """)
    }
}
