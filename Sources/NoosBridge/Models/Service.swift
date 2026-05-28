// Service.swift — capability protocol (Phase 2a, ported from iMCP architecture).
//
// Each personal-data source (Messages, Calendar, Contacts, WhatsApp, …)
// conforms to Service. The BridgeController collects all activated services
// and exposes the union of their tools to the cloud broker through the
// MCP-shaped invoke wire.
//
// Pattern from iMCP/App/Models/Service.swift — adapted to remove their
// Ontology/JSON-LD dependency and align with our existing ToolDispatcher
// shape (snake_case tool names, plain JSON results).

import Foundation

@preconcurrency
protocol Service: Sendable {
    /// Stable identifier — `imessage`, `calendar`, etc. Used as the
    /// `source` in `{type:'status', source, state}` frames.
    var id: String { get }

    /// Tools this service exposes. Static for v1; later we'll allow runtime
    /// changes (e.g. WhatsApp gains tools after pairing) and emit
    /// `notifications/tools/list_changed` on the wire.
    var tools: [Tool] { get }

    /// Has the user granted whatever permissions this service needs?
    /// Computed at call time so toggle changes in System Settings are seen.
    var isActivated: Bool { get async }

    /// Trigger the system permission flow (TCC popup, FDA wizard, etc).
    /// Throws a typed `ServiceError` on denial / other unrecoverable failure.
    func activate() async throws
}

enum ServiceError: Error, LocalizedError {
    case permissionDenied(source: String, remediation: String?)
    case notConfigured(source: String, message: String)
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let source, let remediation):
            return "Permission denied for \(source)" + (remediation.map { ": \($0)" } ?? "")
        case .notConfigured(let source, let message):
            return "\(source) not configured: \(message)"
        case .underlying(let err):
            return err.localizedDescription
        }
    }
}
