import Foundation

public struct PathEvaluation: Sendable {
    public enum Outcome: Sendable, Equatable {
        case allowed
        case denied
    }

    public var outcome: Outcome
    public var grant: PathGrant?
    public var reason: String?

    public var isAllowed: Bool { outcome == .allowed }

    public static func allowed(_ grant: PathGrant) -> PathEvaluation {
        PathEvaluation(outcome: .allowed, grant: grant, reason: nil)
    }

    public static func denied(_ reason: String) -> PathEvaluation {
        PathEvaluation(outcome: .denied, grant: nil, reason: reason)
    }
}

/// Decides whether a path is covered by the configured grants.
public struct PathPolicy: Sendable {
    public let grants: [PathGrant]

    public init(grants: [PathGrant]) {
        self.grants = grants
    }

    public func evaluate(path: String, operation: FileOperation) -> PathEvaluation {
        let target = Self.normalize(path)
        var writeFailureReason: String?

        for grant in grants {
            let granted = Self.normalize(grant.path)
            guard Self.covers(granted: granted, target: target, recursive: grant.recursive) else {
                continue
            }
            if operation.isWrite && !grant.mode.canWrite {
                writeFailureReason = "grant for '\(grant.path)' is read-only"
                continue
            }
            return .allowed(grant)
        }

        if let writeFailureReason {
            return .denied(writeFailureReason)
        }
        return .denied("no grant covers '\(target)'")
    }

    public static func normalize(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let standardized = URL(fileURLWithPath: expanded).standardizedFileURL
        return standardized.resolvingSymlinksInPath().path
    }

    public static func covers(granted: String, target: String, recursive: Bool) -> Bool {
        if target == granted { return true }
        guard recursive else { return false }
        let prefix = granted.hasSuffix("/") ? granted : granted + "/"
        return target.hasPrefix(prefix)
    }
}
