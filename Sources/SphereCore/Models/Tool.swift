import Foundation

/// A tool exposed to the language model. `name` is namespaced (`<module>_<tool>`)
/// while `originalName` is what the provider (MCP server or broker) expects.
public struct ToolDefinition: Codable, Sendable, Identifiable {
    public var name: String
    public var originalName: String
    public var moduleId: String
    public var description: String
    public var inputSchema: JSONValue?

    public var id: String { name }

    public init(
        name: String,
        originalName: String,
        moduleId: String,
        description: String,
        inputSchema: JSONValue? = nil
    ) {
        self.name = name
        self.originalName = originalName
        self.moduleId = moduleId
        self.description = description
        self.inputSchema = inputSchema
    }

    public static func namespaced(moduleId: String, toolName: String) -> String {
        let module = moduleId.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        let tool = toolName.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        return "\(module)_\(tool)"
    }
}

public struct ToolOutcome: Sendable {
    public var text: String
    public var isError: Bool
    public var raw: JSONValue?

    public init(text: String, isError: Bool = false, raw: JSONValue? = nil) {
        self.text = text
        self.isError = isError
        self.raw = raw
    }
}

/// A tool call emitted by the model.
public struct LLMToolCall: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var arguments: JSONValue

    public init(id: String = UUID().uuidString, name: String, arguments: JSONValue) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}
