import Foundation
import SphereCore

enum ToolSchemas {
    static func object(properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map { JSONValue.string($0) }),
        ])
    }

    static func string(_ description: String? = nil) -> JSONValue {
        var value: [String: JSONValue] = ["type": .string("string")]
        if let description { value["description"] = .string(description) }
        return .object(value)
    }

    static func integer(_ description: String? = nil) -> JSONValue {
        var value: [String: JSONValue] = ["type": .string("integer")]
        if let description { value["description"] = .string(description) }
        return .object(value)
    }

    static func boolean(_ description: String? = nil) -> JSONValue {
        var value: [String: JSONValue] = ["type": .string("boolean")]
        if let description { value["description"] = .string(description) }
        return .object(value)
    }

    static func stringArray(_ description: String? = nil) -> JSONValue {
        var value: [String: JSONValue] = [
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
        ]
        if let description { value["description"] = .string(description) }
        return .object(value)
    }

    static func choice(_ values: [String], _ description: String? = nil) -> JSONValue {
        var value: [String: JSONValue] = [
            "type": .string("string"),
            "enum": .array(values.map { JSONValue.string($0) }),
        ]
        if let description { value["description"] = .string(description) }
        return .object(value)
    }
}
