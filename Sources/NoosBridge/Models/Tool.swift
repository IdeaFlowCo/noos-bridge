// Tool.swift — single tool descriptor + invocation wrapper.
//
// MCP-spec-friendly: name, description, JSON-Schema inputSchema, and an
// async implementation closure that returns Encodable. Mirrors the shape
// returned by /api/bridge/mcp/tools/list on the server side.

import Foundation

struct Tool: Sendable {
    let name: String                  // e.g. "imessage.search"
    let description: String
    let inputSchema: JSONSchema
    let implementation: @Sendable ([String: AnyDecodable]) async throws -> AnyEncodable
}

/// Minimal JSON Schema representation. We don't need the full spec —
/// just enough for `properties` + `required` + types. Keep it dumb.
struct JSONSchema: Encodable, Sendable {
    let type: String
    let properties: [String: JSONSchemaProperty]
    let required: [String]
    let additionalProperties: Bool

    init(properties: [String: JSONSchemaProperty], required: [String] = [], additionalProperties: Bool = false) {
        self.type = "object"
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
    }
}

struct JSONSchemaProperty: Encodable, Sendable {
    let type: String                  // "string" | "integer" | "boolean" | "array" | "object"
    let description: String?
    let minimum: Int?
    let maximum: Int?
    let `default`: AnyEncodable?

    init(type: String,
         description: String? = nil,
         minimum: Int? = nil,
         maximum: Int? = nil,
         default defaultValue: AnyEncodable? = nil) {
        self.type = type
        self.description = description
        self.minimum = minimum
        self.maximum = maximum
        self.default = defaultValue
    }
}
