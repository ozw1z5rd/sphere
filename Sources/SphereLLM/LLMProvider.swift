import Foundation
import SphereCore

public protocol LLMProvider: AnyObject, Sendable {
    var id: String { get }
    var displayName: String { get }
    func stream(request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error>
    func listModels() async throws -> [LLMModel]
}

public extension LLMProvider {
    func listModels() async throws -> [LLMModel] { [] }
}

public enum LLMProviderFactory {
    public static func make(
        config: ProviderConfig,
        apiKey: String?,
        debugLogging: Bool = false
    ) -> LLMProvider? {
        switch config.kind {
        case .openAICompatible:
            return OpenAICompatibleProvider(config: config, apiKey: apiKey, debugLogging: debugLogging)
        case .anthropic:
            return AnthropicProvider(config: config, apiKey: apiKey, debugLogging: debugLogging)
        }
    }
}
