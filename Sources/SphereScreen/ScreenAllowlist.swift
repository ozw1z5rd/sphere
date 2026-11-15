import Foundation
import SphereCore

/// Enforces the per-window consent model. macOS grants Screen Recording at the
/// app level, so Sphere keeps its own allowlist and checks it before capture.
public final class ScreenAllowlist {
    private let store: PermissionStore

    public init(store: PermissionStore) {
        self.store = store
    }

    public func authorization(for window: WindowInfo) throws -> ScreenGrant? {
        let grants = try store.screenGrants()
        for grant in grants where grant.enabled {
            if let windowId = grant.windowId, windowId == window.id {
                return grant
            }
            if let bundleId = grant.bundleId, let windowBundle = window.bundleId, bundleId == windowBundle {
                return grant
            }
            if grant.bundleId == nil, grant.windowId == nil, grant.appName == window.appName {
                return grant
            }
        }
        return nil
    }

    public func isAllowed(_ window: WindowInfo) throws -> Bool {
        try authorization(for: window) != nil
    }

    @discardableResult
    public func allow(window: WindowInfo, scope: GrantScope = .persistent) throws -> ScreenGrant {
        let existing = try authorization(for: window)
        if let existing { return existing }
        let grant = ScreenGrant(
            bundleId: window.bundleId,
            appName: window.appName,
            windowTitle: window.title,
            windowId: scope == .session ? window.id : nil,
            enabled: true
        )
        try store.addScreenGrant(grant)
        return grant
    }

    public func revoke(grantId: String) throws {
        try store.removeScreenGrant(id: grantId)
    }

    public func recordCapture(grantId: String) throws {
        try store.recordScreenCapture(grantId: grantId)
    }
}
