import Foundation
import SphereCore

/// Built-in tool that fetches HTTP(S) URLs. Every request is checked against
/// the user's ban rules before and after redirects.
public final class WebToolProvider: ToolProvider {
    public let moduleId = "sphere.web"
    public let providerName = "Web Fetch"

    private let policy: NetworkPolicy
    private let store: NetworkStore
    private let audit: AuditLog
    private let session: URLSession
    private let defaultMaxBytes: Int
    private let maxOutputCharacters: Int

    public init(
        policy: NetworkPolicy,
        store: NetworkStore,
        audit: AuditLog = AuditLog(),
        defaultMaxBytes: Int = 200_000,
        maxOutputCharacters: Int = 50_000
    ) {
        self.policy = policy
        self.store = store
        self.audit = audit
        self.defaultMaxBytes = defaultMaxBytes
        self.maxOutputCharacters = maxOutputCharacters

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    public func definitions() -> [ToolDefinition] {
        [
            ToolDefinition(
                name: ToolDefinition.namespaced(moduleId: moduleId, toolName: "web_fetch"),
                originalName: "web_fetch",
                moduleId: moduleId,
                description: "Fetch an http(s) URL and return its content as text. Blocked by the user's URL/domain/IP ban list.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "url": .object(["type": .string("string")]),
                        "format": .object([
                            "type": .string("string"),
                            "enum": .array([.string("text"), .string("raw")]),
                            "description": .string("Use 'raw' to keep HTML instead of extracting text."),
                        ]),
                        "max_bytes": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum bytes to read (default 200000, max 2000000)."),
                        ]),
                    ]),
                    "required": .array([.string("url")]),
                ])
            ),
        ]
    }

    public func invoke(tool: String, arguments: JSONValue) async throws -> ToolOutcome {
        guard tool == "web_fetch" else {
            throw SphereError.protocolError("unknown web tool '\(tool)'")
        }
        guard let raw = arguments["url"]?.stringValue, !raw.isEmpty else {
            throw SphereError.protocolError("missing argument 'url'")
        }

        let requested = raw.contains("://") ? raw : "https://" + raw
        guard let url = URL(string: requested), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw SphereError.protocolError("invalid or unsupported URL '\(raw)'")
        }
        guard let host = url.host, !host.isEmpty else {
            throw SphereError.protocolError("URL has no host")
        }

        try await authorize(url: url, host: host)

        let format = arguments["format"]?.stringValue ?? "text"
        let requestedBytes = arguments["max_bytes"]?.numberValue.map { Int($0) } ?? defaultMaxBytes
        let maxBytes = min(max(requestedBytes, 1_000), 2_000_000)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Sphere/0.1 (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue(
            "text/html,application/json,text/plain,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SphereError.protocolError("missing HTTP response")
        }

        if let finalURL = http.url, finalURL != url {
            try await authorize(url: finalURL, host: finalURL.host ?? host)
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
        let truncated = data.count > maxBytes
        let slice = Data(data.prefix(maxBytes))

        var body: String
        if format != "raw" && contentType.lowercased().contains("html") {
            body = Self.htmlToText(slice)
        } else {
            body = String(data: slice, encoding: .utf8) ?? "<\(slice.count) bytes of binary content>"
        }
        if body.count > maxOutputCharacters {
            body = String(body.prefix(maxOutputCharacters)) + "\n… output truncated at \(maxOutputCharacters) characters"
        }
        if truncated {
            body += "\n… response truncated at \(maxBytes) bytes"
        }

        audit.write("web", "GET \(http.url?.absoluteString ?? url.absoluteString) -> \(http.statusCode)")

        let header = """
        URL: \(http.url?.absoluteString ?? url.absoluteString)
        Status: \(http.statusCode)
        Content-Type: \(contentType)
        Bytes: \(data.count)

        """
        return ToolOutcome(
            text: header + body,
            isError: !(200..<400).contains(http.statusCode)
        )
    }

    private func authorize(url: URL, host: String) async throws {
        let evaluation = await policy.evaluate(url: url)
        let detail: String?
        if evaluation.blocked {
            detail = [evaluation.reason, evaluation.rule.map { "rule=\($0.value)" }]
                .compactMap { $0 }
                .joined(separator: " · ")
        } else {
            detail = evaluation.reason
        }
        let event = NetworkEvent(
            url: url.absoluteString,
            host: host,
            allowed: !evaluation.blocked,
            ruleId: evaluation.rule?.id,
            detail: detail
        )
        try? store.recordEvent(event)

        if evaluation.blocked {
            if let rule = evaluation.rule {
                try? store.recordBlocked(ruleId: rule.id)
                audit.write("web", "BLOCKED \(url.absoluteString) by \(rule.kind.rawValue) rule '\(rule.value)'")
            }
            throw SphereError.permissionDenied(
                "URL blocked by ban rule: \(evaluation.rule?.value ?? "unknown")"
            )
        }
    }

    static func htmlToText(_ data: Data) -> String {
        guard let html = String(data: data, encoding: .utf8) else {
            return "<\(data.count) bytes of non-UTF8 content>"
        }
        var text = html
        text = text.replacingOccurrences(
            of: "(?is)<script[^>]*>.*?</script>",
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "(?is)<style[^>]*>.*?</style>",
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
        let entities: [String: String] = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(of: "[\\t\\r\\f]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
