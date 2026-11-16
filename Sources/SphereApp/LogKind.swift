import SwiftUI

/// The database-backed logs shown in the dedicated Logs window.
public enum LogKind: String, CaseIterable, Identifiable {
    case fileAccess
    case network
    case tools
    case clipboard
    case http
    case keychain

    public var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .fileAccess: return "File Access"
        case .network: return "Network"
        case .tools: return "Tools"
        case .clipboard: return "Clipboard"
        case .http: return "HTTP"
        case .keychain: return "Keychain"
        }
    }

    var systemImage: String {
        switch self {
        case .fileAccess: return "folder"
        case .network: return "globe"
        case .tools: return "wrench.and.screwdriver"
        case .clipboard: return "doc.on.clipboard"
        case .http: return "arrow.up.arrow.down"
        case .keychain: return "key.fill"
        }
    }
}
