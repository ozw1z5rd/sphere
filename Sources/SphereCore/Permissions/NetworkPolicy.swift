import Foundation
import Darwin

public struct NetworkEvaluation: Sendable {
    public var blocked: Bool
    public var rule: NetworkRule?
    public var reason: String?
    public var resolvedIPs: [String]
}

/// Evaluates a request URL against the user's ban list. Default is allow;
/// matching rules block. Supports URL prefixes, domains and IP/CIDR entries.
public final class NetworkPolicy {
    private let store: NetworkStore

    public init(store: NetworkStore) {
        self.store = store
    }

    public func evaluate(url: URL) async -> NetworkEvaluation {
        let host = (url.host ?? "").lowercased()
        let absolute = url.absoluteString
        let enabled = ((try? store.rules()) ?? []).filter(\.enabled)

        var ipRules: [NetworkRule] = []
        for rule in enabled {
            switch rule.kind {
            case .url:
                if Self.matchesURL(rule.value, absolute) {
                    return blocked(rule, reason: "URL matches banned prefix")
                }
            case .domain:
                if Self.matchesDomain(rule.value, host) {
                    return blocked(rule, reason: "domain is banned")
                }
            case .ip:
                ipRules.append(rule)
            }
        }

        guard !ipRules.isEmpty else {
            return NetworkEvaluation(blocked: false, rule: nil, reason: nil, resolvedIPs: [])
        }

        let resolved = await Self.resolveIPs(host: host)
        for rule in ipRules where Self.matchesIP(rule.value, host: host, resolved: resolved) {
            return blocked(rule, reason: "IP is banned")
        }
        return NetworkEvaluation(blocked: false, rule: nil, reason: nil, resolvedIPs: resolved)
    }

    private func blocked(_ rule: NetworkRule, reason: String) -> NetworkEvaluation {
        NetworkEvaluation(blocked: true, rule: rule, reason: reason, resolvedIPs: [])
    }

    // MARK: - Rule validation

    /// Normalizes and validates a user-entered ban rule. Returns nil if invalid.
    public static func normalizeRuleValue(_ raw: String, kind: NetworkRuleKind) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch kind {
        case .url:
            let value = trimmed.contains("://") ? trimmed : "https://" + trimmed
            guard let url = URL(string: value), let host = url.host, !host.isEmpty else { return nil }
            return value

        case .domain:
            var host = trimmed.lowercased()
            if let url = URL(string: trimmed), let parsed = url.host {
                host = parsed.lowercased()
            } else if let url = URL(string: "https://" + trimmed), let parsed = url.host {
                host = parsed.lowercased()
            }
            host = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host.isEmpty ? nil : host

        case .ip:
            if trimmed.contains("/") {
                let parts = trimmed.split(separator: "/")
                guard parts.count == 2,
                      let bits = Int(parts[1]),
                      (0...32).contains(bits),
                      ipv4ToUInt32(String(parts[0])) != nil
                else {
                    return nil
                }
                return trimmed
            }
            if ipv4ToUInt32(trimmed) != nil {
                return trimmed
            }
            if trimmed.contains(":"),
               trimmed.allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "." }) {
                return trimmed
            }
            return nil
        }
    }

    // MARK: - Matching

    static func matchesURL(_ ruleValue: String, _ absolute: String) -> Bool {
        let value = ruleValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return false }
        return absolute.lowercased().hasPrefix(value)
    }

    static func matchesDomain(_ ruleValue: String, _ host: String) -> Bool {
        let value = ruleValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !value.isEmpty, !host.isEmpty else { return false }
        return host == value || host.hasSuffix("." + value)
    }

    static func matchesIP(_ ruleValue: String, host: String, resolved: [String]) -> Bool {
        let value = ruleValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        if value.contains("/") {
            if cidrContains(value, ip: host) { return true }
            return resolved.contains { cidrContains(value, ip: $0) }
        }
        if host.caseInsensitiveCompare(value) == .orderedSame { return true }
        return resolved.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
    }

    // MARK: - IPv4 CIDR

    static func ipv4ToUInt32(_ string: String) -> UInt32? {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part) else { return nil }
            value = (value << 8) | UInt32(octet)
        }
        return value
    }

    static func cidrContains(_ cidr: String, ip: String) -> Bool {
        let components = cidr.split(separator: "/")
        guard components.count == 2,
              let base = ipv4ToUInt32(String(components[0])),
              let bits = Int(components[1]),
              (0...32).contains(bits),
              let target = ipv4ToUInt32(ip)
        else {
            return false
        }
        let mask: UInt32 = bits == 0 ? 0 : ~UInt32(0) << UInt32(32 - bits)
        return (base & mask) == (target & mask)
    }

    // MARK: - DNS

    public static func resolveIPs(host: String) async -> [String] {
        guard !host.isEmpty else { return [] }
        return await Task.detached(priority: .utility) {
            resolveIPv4AndIPv6(host)
        }.value
    }

    private static func resolveIPv4AndIPv6(_ host: String) -> [String] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0 else { return [] }
        defer { freeaddrinfo(result) }

        var addresses: Set<String> = []
        var pointer = result
        while let info = pointer {
            if let address = info.pointee.ai_addr {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let length = socklen_t(info.pointee.ai_addrlen)
                if getnameinfo(
                    address,
                    length,
                    &buffer,
                    socklen_t(buffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    addresses.insert(String(cString: buffer))
                }
            }
            pointer = info.pointee.ai_next
        }
        return Array(addresses)
    }
}
