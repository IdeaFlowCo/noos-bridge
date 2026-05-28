// Calendar.swift — Apple Calendar capability via EventKit.
//
// Permission: Calendar full-access (TCC popup, no FDA needed). On macOS 14+
// the API is requestFullAccessToEvents(); on 13 it's requestAccess(for:).
// Our deployment target is 13, so we branch.
//
// Tools (Phase 4):
//   - calendar_list_events   — events in a time window
//   - calendar_search_events — text search across events

import Foundation
import EventKit
import AppKit

struct CalendarService: Service {
    let id = "calendar"

    private let store = EKEventStore()

    var tools: [Tool] {
        [
            calendarListEventsTool,
            calendarSearchEventsTool,
        ]
    }

    var isActivated: Bool {
        get async {
            let status = EKEventStore.authorizationStatus(for: .event)
            if #available(macOS 14, *) {
                return status == .fullAccess
            } else {
                return status == .authorized
            }
        }
    }

    func activate() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .denied, .restricted:
            throw ServiceError.permissionDenied(
                source: id,
                remediation: "Open System Settings → Privacy & Security → Calendars and toggle on \(AppInfo.displayName)."
            )
        default: break
        }

        if #available(macOS 14, *) {
            do {
                let granted = try await store.requestFullAccessToEvents()
                if !granted {
                    throw ServiceError.permissionDenied(source: id, remediation: nil)
                }
            } catch {
                throw ServiceError.underlying(error)
            }
        } else {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                store.requestAccess(to: .event) { granted, error in
                    if let error { cont.resume(throwing: ServiceError.underlying(error)); return }
                    if !granted { cont.resume(throwing: ServiceError.permissionDenied(source: "calendar", remediation: nil)); return }
                    cont.resume(returning: ())
                }
            }
        }
    }

    // MARK: - Tool descriptors

    private var calendarListEventsTool: Tool {
        Tool(
            name: "calendar.list_events",
            description: "List the user's calendar events in a time window (defaults to next 7 days). Returns title, start, end, location, calendar, and notes.",
            inputSchema: JSONSchema(
                properties: [
                    "since":  JSONSchemaProperty(type: "string",  description: "ISO 8601 start of window. Default: now."),
                    "until":  JSONSchemaProperty(type: "string",  description: "ISO 8601 end of window. Default: 7 days from now."),
                    "limit":  JSONSchemaProperty(type: "integer", description: "Max events. Default 50.", minimum: 1, maximum: 200),
                ]
            ),
            implementation: { args in
                try await Self.runListEvents(store: self.store, args: args)
            }
        )
    }

    private var calendarSearchEventsTool: Tool {
        Tool(
            name: "calendar.search_events",
            description: "Search the user's calendar events by title text (case-insensitive substring). Optionally bounded by since/until window.",
            inputSchema: JSONSchema(
                properties: [
                    "query":  JSONSchemaProperty(type: "string",  description: "Substring to match against title. Required."),
                    "since":  JSONSchemaProperty(type: "string",  description: "ISO 8601 start. Default: 365 days ago."),
                    "until":  JSONSchemaProperty(type: "string",  description: "ISO 8601 end. Default: 90 days from now."),
                    "limit":  JSONSchemaProperty(type: "integer", description: "Max events. Default 20.", minimum: 1, maximum: 100),
                ],
                required: ["query"]
            ),
            implementation: { args in
                try await Self.runSearchEvents(store: self.store, args: args)
            }
        )
    }

    // MARK: - Implementations

    private static func runListEvents(store: EKEventStore, args: [String: AnyDecodable]) async throws -> AnyEncodable {
        let now = Date()
        let since = parseDate(args["since"]?.stringValue) ?? now
        let until = parseDate(args["until"]?.stringValue) ?? now.addingTimeInterval(7 * 86400)
        let limit = args["limit"]?.intValue ?? 50

        let predicate = store.predicateForEvents(withStart: since, end: until, calendars: nil)
        let events = store.events(matching: predicate)
        let trimmed = Array(events.prefix(limit))
        return AnyEncodable([
            "events": trimmed.map(eventDict),
            "count":  trimmed.count,
        ])
    }

    private static func runSearchEvents(store: EKEventStore, args: [String: AnyDecodable]) async throws -> AnyEncodable {
        guard let query = args["query"]?.stringValue, !query.isEmpty else {
            throw ServiceError.notConfigured(source: "calendar", message: "query is required")
        }
        let now = Date()
        let since = parseDate(args["since"]?.stringValue) ?? now.addingTimeInterval(-365 * 86400)
        let until = parseDate(args["until"]?.stringValue) ?? now.addingTimeInterval(90 * 86400)
        let limit = args["limit"]?.intValue ?? 20

        let predicate = store.predicateForEvents(withStart: since, end: until, calendars: nil)
        let matches = store.events(matching: predicate)
            .filter { $0.title?.localizedCaseInsensitiveContains(query) ?? false }
            .prefix(limit)

        return AnyEncodable([
            "events": matches.map(eventDict),
            "count":  matches.count,
        ])
    }

    private static func eventDict(_ ev: EKEvent) -> [String: Any] {
        [
            "id":        ev.eventIdentifier ?? "",
            "title":     ev.title ?? "",
            "start":     iso(ev.startDate),
            "end":       iso(ev.endDate),
            "location":  ev.location ?? "",
            "calendar":  ev.calendar?.title ?? "",
            "notes":     ev.notes ?? "",
            "isAllDay":  ev.isAllDay,
        ]
    }

    private static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
