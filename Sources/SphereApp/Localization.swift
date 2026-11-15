import Foundation

/// Minimal localization helper for strings that are produced in code (status
/// messages, notifications, formatted counters). SwiftUI string literals are
/// localized through the environment locale; these helpers cover the rest.
enum L10n {
    static let supportedLanguages = ["en", "it"]

    private(set) static var languageCode = systemLanguageCode()
    private(set) static var bundle = localizationBundle(for: languageCode)

    static var locale: Locale {
        Locale(identifier: languageCode)
    }

    static func setLanguage(_ code: String?) {
        let resolved: String
        if let code, supportedLanguages.contains(code) {
            resolved = code
        } else {
            resolved = systemLanguageCode()
        }
        languageCode = resolved
        bundle = localizationBundle(for: resolved)
    }

    static func t(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), arguments: arguments)
    }

    private static func systemLanguageCode() -> String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        let code = String(preferred.prefix(2))
        return supportedLanguages.contains(code) ? code : "en"
    }

    private static func localizationBundle(for code: String) -> Bundle {
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        if let path = Bundle.module.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }
}
