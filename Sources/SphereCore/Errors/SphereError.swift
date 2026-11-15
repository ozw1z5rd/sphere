import Foundation

public enum SphereError: LocalizedError, Equatable {
    case invalidManifest(String)
    case unsupportedManifestVersion(Int)
    case duplicateModule(String)
    case moduleNotFound(String)
    case moduleDisabled(String)
    case archiveExtractionFailed(String)
    case checksumMismatch
    case transportUnavailable
    case processFailed(String)
    case timeout(String)
    case protocolError(String)
    case permissionDenied(String)
    case pathOutsideGrant(String)
    case notConfigured(String)

    public var errorDescription: String? {
        switch self {
        case .invalidManifest(let detail):
            return "Invalid module manifest: \(detail)"
        case .unsupportedManifestVersion(let version):
            return "Unsupported manifest schemaVersion: \(version)"
        case .duplicateModule(let id):
            return "A module with id '\(id)' is already installed"
        case .moduleNotFound(let id):
            return "Module '\(id)' is not installed"
        case .moduleDisabled(let id):
            return "Module '\(id)' is disabled"
        case .archiveExtractionFailed(let detail):
            return "Could not extract module archive: \(detail)"
        case .checksumMismatch:
            return "Checksum mismatch while validating module archive"
        case .transportUnavailable:
            return "MCP transport is not available"
        case .processFailed(let detail):
            return "Process failed: \(detail)"
        case .timeout(let detail):
            return "Timed out: \(detail)"
        case .protocolError(let detail):
            return "Protocol error: \(detail)"
        case .permissionDenied(let detail):
            return "Permission denied: \(detail)"
        case .pathOutsideGrant(let path):
            return "Path is outside the granted roots: \(path)"
        case .notConfigured(let detail):
            return "Not configured: \(detail)"
        }
    }
}
