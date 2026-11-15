import Foundation
import SphereCore

public struct MCPError: Codable, Sendable, Error {
    public let code: Int
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

struct JSONRPCMessage: Codable, Sendable {
    var jsonrpc: String = "2.0"
    var id: Int?
    var method: String?
    var params: JSONValue?
    var result: JSONValue?
    var error: MCPError?

    static func request(id: Int, method: String, params: JSONValue? = nil) -> JSONRPCMessage {
        JSONRPCMessage(id: id, method: method, params: params)
    }

    static func notification(method: String, params: JSONValue? = nil) -> JSONRPCMessage {
        JSONRPCMessage(method: method, params: params)
    }
}

public struct MCPTool: Codable, Sendable, Identifiable {
    public var name: String
    public var title: String?
    public var description: String?
    public var inputSchema: JSONValue?

    public var id: String { name }

    public init(name: String, title: String? = nil, description: String? = nil, inputSchema: JSONValue? = nil) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct MCPServerInfo: Codable, Sendable {
    public var name: String?
    public var version: String?
    public var protocolVersion: String?
    public var instructions: String?
}

public struct ToolInvocationResult: Sendable {
    public var content: [ToolContent]
    public var isError: Bool
    public var raw: JSONValue

    public init(content: [ToolContent], isError: Bool, raw: JSONValue) {
        self.content = content
        self.isError = isError
        self.raw = raw
    }
}

public struct ToolContent: Sendable {
    public var type: String
    public var text: String?
    public var data: String?
    public var mimeType: String?

    public init(type: String, text: String? = nil, data: String? = nil, mimeType: String? = nil) {
        self.type = type
        self.text = text
        self.data = data
        self.mimeType = mimeType
    }
}
