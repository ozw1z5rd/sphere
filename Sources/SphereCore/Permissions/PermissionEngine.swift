import Foundation

public struct AccessDecision: Sendable {
    public var allowed: Bool
    public var grant: PathGrant?
    public var reason: String?
    public var event: AccessEvent?
}

/// Central gate for file access. Every broker operation goes through here so
/// that grants and access counters stay authoritative.
public final class PermissionEngine {
    private let store: PermissionStore

    public init(store: PermissionStore) {
        self.store = store
    }

    /// Pure evaluation; does not record an audit event.
    public func check(path: String, operation: FileOperation) throws -> PathEvaluation {
        let grants = try store.pathGrants()
        return PathPolicy(grants: grants).evaluate(path: path, operation: operation)
    }

    /// Evaluates and records an audit event, updating per-grant counters.
    public func authorize(moduleId: String, sessionId: String? = nil, path: String, operation: FileOperation) throws -> AccessDecision {
        let evaluation = try check(path: path, operation: operation)
        let event = AccessEvent(
            grantId: evaluation.grant?.id,
            sessionId: sessionId,
            moduleId: moduleId,
            path: PathPolicy.normalize(path),
            operation: operation,
            allowed: evaluation.isAllowed,
            detail: evaluation.reason
        )
        try store.recordAccess(event)
        return AccessDecision(
            allowed: evaluation.isAllowed,
            grant: evaluation.grant,
            reason: evaluation.reason,
            event: event
        )
    }

    /// Throws unless the path is allowed for the given operation.
    @discardableResult
    public func require(moduleId: String, sessionId: String? = nil, path: String, operation: FileOperation) throws -> PathGrant {
        let decision = try authorize(moduleId: moduleId, sessionId: sessionId, path: path, operation: operation)
        guard decision.allowed, let grant = decision.grant else {
            throw SphereError.pathOutsideGrant(PathPolicy.normalize(path))
        }
        return grant
    }
}
