import Foundation

public struct ModelPricing: Sendable {
    public var inputPerMillion: Double
    public var outputPerMillion: Double

    public init(inputPerMillion: Double, outputPerMillion: Double) {
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
    }
}

public enum Pricing {
    private static let catalog: [String: ModelPricing] = [
        "gpt-4o-mini": ModelPricing(inputPerMillion: 0.15, outputPerMillion: 0.60),
        "gpt-4o": ModelPricing(inputPerMillion: 2.50, outputPerMillion: 10.00),
        "gpt-4.1-mini": ModelPricing(inputPerMillion: 0.40, outputPerMillion: 1.60),
        "gpt-4.1": ModelPricing(inputPerMillion: 2.00, outputPerMillion: 8.00),
        "claude-3-5-sonnet": ModelPricing(inputPerMillion: 3.00, outputPerMillion: 15.00),
        "claude-3-5-haiku": ModelPricing(inputPerMillion: 0.80, outputPerMillion: 4.00),
        "claude-sonnet-4": ModelPricing(inputPerMillion: 3.00, outputPerMillion: 15.00),
        "deepseek-chat": ModelPricing(inputPerMillion: 0.14, outputPerMillion: 0.28),
        "deepseek-reasoner": ModelPricing(inputPerMillion: 0.55, outputPerMillion: 2.19),
    ]

    public static func pricing(for model: String) -> ModelPricing? {
        let key = model.lowercased()
        if let exact = catalog[key] {
            return exact
        }
        for (name, pricing) in catalog where key.contains(name) {
            return pricing
        }
        return nil
    }

    public static func cost(model: String, promptTokens: Int, completionTokens: Int) -> Double? {
        guard let pricing = pricing(for: model) else { return nil }
        let input = Double(promptTokens) / 1_000_000 * pricing.inputPerMillion
        let output = Double(completionTokens) / 1_000_000 * pricing.outputPerMillion
        return input + output
    }
}
