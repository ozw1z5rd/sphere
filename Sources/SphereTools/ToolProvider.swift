import Foundation
import SphereCore

public protocol ToolProvider: AnyObject {
    var moduleId: String { get }
    var providerName: String { get }
    func definitions() -> [ToolDefinition]
    func invoke(tool: String, arguments: JSONValue, sessionId: String?) async throws -> ToolOutcome
}
