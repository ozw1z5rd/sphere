import Foundation

public extension ModuleManifest {
    /// Returns the transport with `${MODULE_DIR}` expanded to the install path.
    func resolvedTransport(installPath: String) -> ModuleTransport? {
        guard var transport else { return nil }
        func expand(_ value: String) -> String {
            value.replacingOccurrences(of: "${MODULE_DIR}", with: installPath)
        }
        transport.command = transport.command.map(expand)
        transport.cwd = transport.cwd.map(expand) ?? installPath
        transport.env = transport.env?.mapValues(expand)
        return transport
    }

    var toolNamespace: String {
        id.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
    }
}
