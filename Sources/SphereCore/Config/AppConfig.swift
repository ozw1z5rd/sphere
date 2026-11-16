import Foundation

public struct ProviderConfig: Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case openAICompatible
        case anthropic
    }

    public var id: String
    public var name: String
    public var kind: Kind
    public var baseURL: String
    public var model: String
    public var maxTokens: Int?
    public var temperature: Double?
    public var topP: Double?
    public var topK: Int?
    public var frequencyPenalty: Double?
    public var presencePenalty: Double?
    public var stopSequences: [String]?
    public var seed: Int?

    public init(
        id: String = UUID().uuidString,
        name: String,
        kind: Kind,
        baseURL: String,
        model: String,
        maxTokens: Int? = 4096,
        temperature: Double? = 0.2,
        topP: Double? = nil,
        topK: Int? = nil,
        frequencyPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        stopSequences: [String]? = nil,
        seed: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.stopSequences = stopSequences
        self.seed = seed
    }

    public static func ollama() -> ProviderConfig {
        ProviderConfig(
            name: "Ollama",
            kind: .openAICompatible,
            baseURL: "http://localhost:11434/v1",
            model: "llama3.1"
        )
    }

    public static func openAI() -> ProviderConfig {
        ProviderConfig(
            name: "OpenAI",
            kind: .openAICompatible,
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini"
        )
    }

    public static func anthropic() -> ProviderConfig {
        ProviderConfig(
            name: "Anthropic",
            kind: .anthropic,
            baseURL: "https://api.anthropic.com",
            model: "claude-3-5-sonnet-latest"
        )
    }

    public static func deepSeek() -> ProviderConfig {
        ProviderConfig(
            name: "DeepSeek",
            kind: .openAICompatible,
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-flash"
        )
    }

    /// Providers shipped with Sphere. Used to seed new configs and to add any
    /// missing entry to existing config files on load.
    public static let builtIn: [ProviderConfig] = [
        .ollama(),
        .openAI(),
        .anthropic(),
        .deepSeek(),
    ]
}

public struct AppConfig: Codable, Sendable {
    public var providers: [ProviderConfig]
    public var activeProviderId: String?
    /// Tool name (`<module>_<tool>`) to policy (`allow`, `ask`, `deny`).
    public var toolPolicy: [String: String]
    /// Extra, user-chosen folders watched for importable module files.
    public var additionalModuleFolders: [String]
    public var screenCaptureEnabled: Bool
    /// When true, full request bodies are written to the HTTP log.
    public var debugHTTPLogging: Bool
    public var speechEnabled: Bool
    public var speechAutoSpeak: Bool
    public var speechVoiceIdentifier: String?
    public var speechRate: Double
    public var userFontName: String?
    public var userFontSize: Double
    /// UI language code (`en`, `it`); `nil` follows the system language.
    public var language: String?
    /// Enables the sandboxed exec tool.
    public var execEnabled: Bool
    /// Allowed command prefixes for exec (e.g. `git status`, `ls`).
    public var execAllowlist: [String]
    /// Namespaced tool names explicitly disabled by the user. Empty = all on.
    public var disabledTools: [String]
    public var assistantFontName: String?
    public var assistantFontSize: Double

    public init(
        providers: [ProviderConfig] = ProviderConfig.builtIn,
        activeProviderId: String? = nil,
        toolPolicy: [String: String] = [:],
        additionalModuleFolders: [String] = [],
        screenCaptureEnabled: Bool = false,
        debugHTTPLogging: Bool = false,
        speechEnabled: Bool = true,
        speechAutoSpeak: Bool = false,
        speechVoiceIdentifier: String? = nil,
        speechRate: Double = 0.5,
        userFontName: String? = nil,
        userFontSize: Double = 13,
        language: String? = nil,
        execEnabled: Bool = false,
        execAllowlist: [String] = [],
        disabledTools: [String] = [],
        assistantFontName: String? = nil,
        assistantFontSize: Double = 13
    ) {
        self.providers = providers
        self.activeProviderId = activeProviderId ?? providers.first?.id
        self.toolPolicy = toolPolicy
        self.additionalModuleFolders = additionalModuleFolders
        self.screenCaptureEnabled = screenCaptureEnabled
        self.debugHTTPLogging = debugHTTPLogging
        self.speechEnabled = speechEnabled
        self.speechAutoSpeak = speechAutoSpeak
        self.speechVoiceIdentifier = speechVoiceIdentifier
        self.speechRate = speechRate
        self.userFontName = userFontName
        self.userFontSize = userFontSize
        self.language = language
        self.execEnabled = execEnabled
        self.execAllowlist = execAllowlist
        self.disabledTools = disabledTools
        self.assistantFontName = assistantFontName
        self.assistantFontSize = assistantFontSize
    }

    private enum CodingKeys: String, CodingKey {
        case providers, activeProviderId, toolPolicy, additionalModuleFolders
        case screenCaptureEnabled, debugHTTPLogging, speechEnabled, speechAutoSpeak
        case speechVoiceIdentifier, speechRate
        case userFontName, userFontSize, assistantFontName, assistantFontSize
        case language, execEnabled, execAllowlist, disabledTools
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.providers = try container.decodeIfPresent([ProviderConfig].self, forKey: .providers)
            ?? ProviderConfig.builtIn
        self.activeProviderId = try container.decodeIfPresent(String.self, forKey: .activeProviderId)
        self.toolPolicy = try container.decodeIfPresent([String: String].self, forKey: .toolPolicy) ?? [:]
        self.additionalModuleFolders = try container.decodeIfPresent([String].self, forKey: .additionalModuleFolders) ?? []
        self.screenCaptureEnabled = try container.decodeIfPresent(Bool.self, forKey: .screenCaptureEnabled) ?? false
        self.debugHTTPLogging = try container.decodeIfPresent(Bool.self, forKey: .debugHTTPLogging) ?? false
        self.speechEnabled = try container.decodeIfPresent(Bool.self, forKey: .speechEnabled) ?? true
        self.speechAutoSpeak = try container.decodeIfPresent(Bool.self, forKey: .speechAutoSpeak) ?? false
        self.speechVoiceIdentifier = try container.decodeIfPresent(String.self, forKey: .speechVoiceIdentifier)
        self.speechRate = try container.decodeIfPresent(Double.self, forKey: .speechRate) ?? 0.5
        self.userFontName = try container.decodeIfPresent(String.self, forKey: .userFontName)
        self.userFontSize = try container.decodeIfPresent(Double.self, forKey: .userFontSize) ?? 13
        self.language = try container.decodeIfPresent(String.self, forKey: .language)
        self.execEnabled = try container.decodeIfPresent(Bool.self, forKey: .execEnabled) ?? false
        self.execAllowlist = try container.decodeIfPresent([String].self, forKey: .execAllowlist) ?? []
        self.disabledTools = try container.decodeIfPresent([String].self, forKey: .disabledTools) ?? []
        self.assistantFontName = try container.decodeIfPresent(String.self, forKey: .assistantFontName)
        self.assistantFontSize = try container.decodeIfPresent(Double.self, forKey: .assistantFontSize) ?? 13
    }

    /// Adds any built-in provider missing from an existing config (matched by
    /// name) so new defaults appear after an upgrade. Returns `true` when the
    /// config changed and should be persisted.
    @discardableResult
    public mutating func mergeBuiltInProviders() -> Bool {
        var changed = false
        let existingNames = Set(providers.map { $0.name.lowercased() })
        for provider in ProviderConfig.builtIn where !existingNames.contains(provider.name.lowercased()) {
            providers.append(provider)
            changed = true
        }
        if activeProviderId == nil {
            activeProviderId = providers.first?.id
            changed = true
        }
        return changed
    }
}

public final class ConfigStore {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(url: URL = AppPaths.config) {
        self.url = url
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let config = AppConfig()
            try save(config)
            return config
        }
        let data = try Data(contentsOf: url)
        var config = try decoder.decode(AppConfig.self, from: data)
        if config.mergeBuiltInProviders() {
            try save(config)
        }
        return config
    }

    public func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }
}
