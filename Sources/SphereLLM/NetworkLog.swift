import Foundation
import SphereCore

/// Logging helpers for provider HTTP traffic. Secrets are always redacted.
enum NetworkLog {
    static func logRequest(provider: String, request: URLRequest, body: Any?, full: Bool) {
        var line = "-> \(provider) \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "?")"
        line += " headers{\(redactedHeaders(request))}"
        if full, let body {
            line += " body=\(truncate(jsonString(body)))"
        }
        SphereLog.http.write("request", line)
    }

    static func logResponse(
        provider: String,
        url: String,
        status: Int,
        body: String,
        full: Bool,
        isSuccess: Bool
    ) {
        let marker = isSuccess ? "<-" : "XX"
        var line = "\(marker) \(provider) \(status) \(url)"
        if !isSuccess || full {
            line += " body=\(truncate(body))"
        }
        SphereLog.http.write("response", line)
    }

    static func redactedHeaders(_ request: URLRequest) -> String {
        let sensitive: Set<String> = ["authorization", "x-api-key", "api-key", "cookie", "proxy-authorization"]
        let headers = request.allHTTPHeaderFields ?? [:]
        return headers
            .map { key, value in
                sensitive.contains(key.lowercased()) ? "\(key): \(mask(value))" : "\(key): \(value)"
            }
            .sorted()
            .joined(separator: ", ")
    }

    static func mask(_ value: String) -> String {
        guard value.count > 8 else { return "***" }
        return "***\(value.suffix(4))"
    }

    static func truncate(_ value: String, limit: Int = 8000) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit)) + "… (\(value.count - limit) more chars)"
    }

    static func jsonString(_ value: Any) -> String {
        guard
            JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            return String(describing: value)
        }
        return text
    }
}
