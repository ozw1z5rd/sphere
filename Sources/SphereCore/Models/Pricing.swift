import Foundation

public struct ModelPricing: Sendable {
    /// Price per 1M input tokens at the base (off-peak / cache-miss) rate.
    public var inputPerMillion: Double
    /// Price per 1M cached input tokens (cache hit). `nil` = same as input.
    public var cachedInputPerMillion: Double?
    /// Price per 1M output tokens at the base rate.
    public var outputPerMillion: Double
    /// Multiplier applied while a peak window is active. `1` = flat pricing.
    public var peakMultiplier: Double
    /// Peak windows as half-open UTC hour ranges, weekdays only. Empty = none.
    public var peakWindowsUTC: [Range<Int>]

    public init(
        inputPerMillion: Double,
        cachedInputPerMillion: Double? = nil,
        outputPerMillion: Double,
        peakMultiplier: Double = 1,
        peakWindowsUTC: [Range<Int>] = []
    ) {
        self.inputPerMillion = inputPerMillion
        self.cachedInputPerMillion = cachedInputPerMillion
        self.outputPerMillion = outputPerMillion
        self.peakMultiplier = peakMultiplier
        self.peakWindowsUTC = peakWindowsUTC
    }

    /// Price multiplier in effect at `date`. Peak windows are evaluated in UTC
    /// against the weekday; public holidays are not modelled, so a holiday
    /// weekday inside a peak window is (over-)estimated at the peak rate.
    public func multiplier(at date: Date) -> Double {
        guard peakMultiplier != 1, !peakWindowsUTC.isEmpty else { return 1 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = calendar.dateComponents([.weekday, .hour], from: date)
        guard let weekday = components.weekday, let hour = components.hour else { return 1 }
        // Calendar weekday: 1 = Sunday … 7 = Saturday.
        guard (2...6).contains(weekday) else { return 1 }
        return peakWindowsUTC.contains { $0.contains(hour) } ? peakMultiplier : 1
    }
}

public enum Pricing {
    /// DeepSeek bills 2x during 01:00–04:00 and 06:00–10:00 UTC, Monday–Friday.
    private static let deepSeekPeakWindows: [Range<Int>] = [1..<4, 6..<10]

    private static func deepSeek(_ input: Double, _ cachedInput: Double, _ output: Double) -> ModelPricing {
        ModelPricing(
            inputPerMillion: input,
            cachedInputPerMillion: cachedInput,
            outputPerMillion: output,
            peakMultiplier: 2,
            peakWindowsUTC: deepSeekPeakWindows
        )
    }

    /// Base rates per 1M tokens. Sources: provider pricing pages, checked
    /// 2026-11-16 (`api-docs.deepseek.com/quick_start/pricing`).
    private static let catalog: [String: ModelPricing] = [
        "gpt-4o-mini": ModelPricing(inputPerMillion: 0.15, outputPerMillion: 0.60),
        "gpt-4o": ModelPricing(inputPerMillion: 2.50, outputPerMillion: 10.00),
        "gpt-4.1-mini": ModelPricing(inputPerMillion: 0.40, outputPerMillion: 1.60),
        "gpt-4.1": ModelPricing(inputPerMillion: 2.00, outputPerMillion: 8.00),
        "claude-3-5-sonnet": ModelPricing(inputPerMillion: 3.00, outputPerMillion: 15.00),
        "claude-3-5-haiku": ModelPricing(inputPerMillion: 0.80, outputPerMillion: 4.00),
        "claude-sonnet-4": ModelPricing(inputPerMillion: 3.00, outputPerMillion: 15.00),
        // DeepSeek V4 line: cache-miss input / cache-hit input / output, off-peak.
        "deepseek-flash": deepSeek(0.15, 0.003, 0.60),
        "deepseek-v4-pro": deepSeek(0.66, 0.022, 1.98),
        // Legacy names still accepted by the API, billed at the Flash price.
        "deepseek-v4-flash": deepSeek(0.15, 0.003, 0.60),
        "deepseek-v4-flash-vision-exp": deepSeek(0.15, 0.003, 0.60),
        // Retired pre-V4 models: kept so older sessions still show a cost.
        "deepseek-chat": ModelPricing(inputPerMillion: 0.14, outputPerMillion: 0.28),
        "deepseek-reasoner": ModelPricing(inputPerMillion: 0.55, outputPerMillion: 2.19),
    ]

    public static func pricing(for model: String) -> ModelPricing? {
        let key = model.lowercased()
        if let exact = catalog[key] {
            return exact
        }
        // Longest match wins, so a dated snapshot such as
        // "gpt-4o-mini-2024-07-18" does not resolve to the pricier "gpt-4o"
        // (dictionary iteration order is otherwise unspecified).
        return catalog
            .filter { key.contains($0.key) }
            .max { $0.key.count < $1.key.count }?
            .value
    }

    public static func cost(
        model: String,
        promptTokens: Int,
        completionTokens: Int,
        cacheHitTokens: Int? = nil,
        cacheMissTokens: Int? = nil,
        at date: Date = Date()
    ) -> Double? {
        guard let pricing = pricing(for: model) else { return nil }
        let cachedPrice = pricing.cachedInputPerMillion ?? pricing.inputPerMillion
        let hit = max(cacheHitTokens ?? 0, 0)
        let miss: Int
        if let cacheMissTokens {
            miss = max(cacheMissTokens, 0)
        } else {
            miss = max(promptTokens - hit, 0)
        }
        let input = Double(hit) / 1_000_000 * cachedPrice
            + Double(miss) / 1_000_000 * pricing.inputPerMillion
        let output = Double(completionTokens) / 1_000_000 * pricing.outputPerMillion
        return (input + output) * pricing.multiplier(at: date)
    }
}
