import Foundation
import Security
import LocalAuthentication

public struct KeychainLookup: Sendable {
    public var value: String?
    public var status: OSStatus
}

/// Stores API keys and other secrets in the macOS Keychain.
public enum Keychain {
    public static let service = "com.sphere.app"

    public static func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            SphereLog.keychain.write("keychain", "set account=\(account) failed status=\(describe(status))")
            throw SphereError.processFailed("keychain write failed (\(describe(status)))")
        }
        SphereLog.keychain.write("keychain", "set account=\(account) ok")
    }

    public static func lookup(account: String, allowUI: Bool = true) -> KeychainLookup {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if !allowUI {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let data = item as? Data {
            let value = String(data: data, encoding: .utf8)
            SphereLog.keychain.write("keychain", "lookup account=\(account) ok length=\(value?.count ?? 0)")
            return KeychainLookup(value: value, status: status)
        }

        SphereLog.keychain.write("keychain", "lookup account=\(account) failed status=\(describe(status))")
        return KeychainLookup(value: nil, status: status)
    }

    public static func get(account: String) -> String? {
        lookup(account: account).value
    }

    public static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        SphereLog.keychain.write("keychain", "delete account=\(account) status=\(describe(status))")
    }

    public static func describe(_ status: OSStatus) -> String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        return "\(status) (\(message))"
    }
}
