// BridgeProtocol.swift — wire frame types for the WSS connection.
//
// Mirrors src/routes/bridge.ts's frame schema verbatim. Any change here
// must be reflected on the server side.

import Foundation

// MARK: - Outgoing frames (Mac → Server)

struct HelloFrame: Encodable {
    let type = "hello"
    let deviceToken: String
    let appVersion: String
    let capabilities: [String]
    let hostname: String
    let macOSVersion: String
    let remoteUnlockAllowed: Bool
}

struct StatusFrame: Encodable {
    let type = "status"
    let source: String
    let state: String
}

struct PongFrame: Encodable { let type = "pong" }
struct LockFrame: Encodable { let type = "lock" }
struct UnlockFrame: Encodable { let type = "unlock" }
struct RemoteUnlockPolicyFrame: Encodable {
    let type = "remote-unlock-policy"
    let allowed: Bool
}

struct ResultErrorPayload: Encodable {
    let code: String
    let message: String
    let remediation: String?
}

struct ResultFrame: Encodable {
    let type = "result"
    let id: String
    let ok: Bool
    let result: AnyEncodable?
    let error: ResultErrorPayload?
}

struct UnlockAttemptResultFrame: Encodable {
    let type = "unlock-attempt-result"
    let id: String
    let ok: Bool
    let reason: String?
}

// MARK: - Incoming frames (Server → Mac)

struct InvokeFrame: Decodable {
    let type: String
    let id: String
    let tool: String
    let args: [String: AnyDecodable]?
    let context: [String: AnyDecodable]?
    let timeoutMs: Int?
}

struct UnlockAttemptFrame: Decodable {
    let type: String
    let id: String
    let password: String
}

struct RestartRequestFrame: Decodable { let type: String }
struct GenericTypeFrame: Decodable { let type: String }

// MARK: - JSON heterogeneous-value helpers (used by Encode/Decode and Tool args)

struct AnyEncodable: Encodable, @unchecked Sendable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { self._encode = value.encode }
    init(_ dict: [String: Any]) {
        self._encode = { encoder in
            var c = encoder.container(keyedBy: AnyCodingKey.self)
            for (k, v) in dict {
                let key = AnyCodingKey(stringValue: k)!
                try AnyEncodable.encodeValue(v, to: &c, forKey: key)
            }
        }
    }
    init(_ array: [Any]) {
        self._encode = { encoder in
            var c = encoder.unkeyedContainer()
            for v in array { try AnyEncodable.encodeUnkeyed(v, to: &c) }
        }
    }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }

    private static func encodeValue(_ v: Any, to c: inout KeyedEncodingContainer<AnyCodingKey>, forKey k: AnyCodingKey) throws {
        switch v {
        case let s as String:           try c.encode(s, forKey: k)
        case let i as Int:              try c.encode(i, forKey: k)
        case let i as Int64:            try c.encode(i, forKey: k)
        case let d as Double:           try c.encode(d, forKey: k)
        case let b as Bool:             try c.encode(b, forKey: k)
        case let dict as [String: Any]: try c.encode(AnyEncodable(dict), forKey: k)
        case let arr as [Any]:          try c.encode(AnyEncodable(arr), forKey: k)
        case Optional<Any>.none:        try c.encodeNil(forKey: k)
        default:                        try c.encode(String(describing: v), forKey: k)
        }
    }
    private static func encodeUnkeyed(_ v: Any, to c: inout UnkeyedEncodingContainer) throws {
        switch v {
        case let s as String:           try c.encode(s)
        case let i as Int:              try c.encode(i)
        case let i as Int64:            try c.encode(i)
        case let d as Double:           try c.encode(d)
        case let b as Bool:             try c.encode(b)
        case let dict as [String: Any]: try c.encode(AnyEncodable(dict))
        case let arr as [Any]:          try c.encode(AnyEncodable(arr))
        default:                        try c.encode(String(describing: v))
        }
    }
}

struct AnyDecodable: Decodable, Sendable {
    let value: AnyValue

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil()                              { value = .null; return }
        if let v = try? c.decode(Bool.self)           { value = .bool(v); return }
        if let v = try? c.decode(Int.self)            { value = .int(v); return }
        if let v = try? c.decode(Double.self)         { value = .double(v); return }
        if let v = try? c.decode(String.self)         { value = .string(v); return }
        if let v = try? c.decode([AnyDecodable].self) { value = .array(v.map { $0.value }); return }
        if let v = try? c.decode([String: AnyDecodable].self) {
            value = .object(v.mapValues { $0.value })
            return
        }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
    }

    /// Convenience: try to interpret as String (also flattens single-element arrays).
    var stringValue: String? {
        if case .string(let s) = value { return s }
        return nil
    }
    /// Convenience: try to interpret as Int (also coerces from Double).
    var intValue: Int? {
        switch value {
        case .int(let i): return i
        case .double(let d): return Int(d)
        default: return nil
        }
    }
}

/// Sendable JSON-value enum (Foundation's Any is not Sendable).
indirect enum AnyValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyValue])
    case object([String: AnyValue])
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    init?(intValue: Int)       { self.stringValue = String(intValue); self.intValue = intValue }
}
