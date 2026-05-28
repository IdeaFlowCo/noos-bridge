// Reminders.swift — Apple Reminders capability via EventKit.
//
// Permission: Reminders full-access on macOS 14+, basic access on 13.
//
// Tools:
//   - reminders_list   — incomplete reminders (defaults), or all
//   - reminders_search — substring match on title

import Foundation
import EventKit

struct RemindersService: Service {
    let id = "reminders"

    private let store = EKEventStore()

    var tools: [Tool] {
        [remindersListTool, remindersSearchTool]
    }

    var isActivated: Bool {
        get async {
            let status = EKEventStore.authorizationStatus(for: .reminder)
            if #available(macOS 14, *) {
                return status == .fullAccess
            } else {
                return status == .authorized
            }
        }
    }

    func activate() async throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .denied, .restricted:
            throw ServiceError.permissionDenied(
                source: id,
                remediation: "Open System Settings → Privacy & Security → Reminders and toggle on \(AppInfo.displayName)."
            )
        default: break
        }

        if #available(macOS 14, *) {
            do {
                let granted = try await store.requestFullAccessToReminders()
                if !granted { throw ServiceError.permissionDenied(source: id, remediation: nil) }
            } catch {
                throw ServiceError.underlying(error)
            }
        } else {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                store.requestAccess(to: .reminder) { granted, error in
                    if let error { cont.resume(throwing: ServiceError.underlying(error)); return }
                    if !granted { cont.resume(throwing: ServiceError.permissionDenied(source: "reminders", remediation: nil)); return }
                    cont.resume(returning: ())
                }
            }
        }
    }

    // MARK: - Tool descriptors

    private var remindersListTool: Tool {
        Tool(
            name: "reminders.list",
            description: "List the user's reminders. By default returns only incomplete ones; pass includeCompleted=true to return all.",
            inputSchema: JSONSchema(
                properties: [
                    "includeCompleted": JSONSchemaProperty(type: "boolean", description: "Include completed reminders. Default false."),
                    "limit":             JSONSchemaProperty(type: "integer", description: "Max reminders. Default 50.", minimum: 1, maximum: 200),
                ]
            ),
            implementation: { args in try await Self.runList(store: self.store, args: args) }
        )
    }

    private var remindersSearchTool: Tool {
        Tool(
            name: "reminders.search",
            description: "Search the user's reminders by title substring (case-insensitive).",
            inputSchema: JSONSchema(
                properties: [
                    "query": JSONSchemaProperty(type: "string", description: "Substring to match against title. Required."),
                    "limit": JSONSchemaProperty(type: "integer", description: "Max reminders. Default 20.", minimum: 1, maximum: 100),
                ],
                required: ["query"]
            ),
            implementation: { args in try await Self.runSearch(store: self.store, args: args) }
        )
    }

    // MARK: - Implementations

    private static func runList(store: EKEventStore, args: [String: AnyDecodable]) async throws -> AnyEncodable {
        let includeCompleted = args["includeCompleted"]?.value == .bool(true)
        let limit            = args["limit"]?.intValue ?? 50

        let predicate: NSPredicate
        if includeCompleted {
            predicate = store.predicateForReminders(in: nil)
        } else {
            predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        }

        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { reminders in
                cont.resume(returning: reminders ?? [])
            }
        }
        let trimmed = Array(reminders.prefix(limit))
        return AnyEncodable([
            "reminders": trimmed.map(reminderDict),
            "count":     trimmed.count,
        ])
    }

    private static func runSearch(store: EKEventStore, args: [String: AnyDecodable]) async throws -> AnyEncodable {
        guard let query = args["query"]?.stringValue, !query.isEmpty else {
            throw ServiceError.notConfigured(source: "reminders", message: "query is required")
        }
        let limit = args["limit"]?.intValue ?? 20

        let predicate = store.predicateForReminders(in: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { reminders in
                cont.resume(returning: reminders ?? [])
            }
        }
        let matches = reminders
            .filter { $0.title?.localizedCaseInsensitiveContains(query) ?? false }
            .prefix(limit)
        return AnyEncodable([
            "reminders": matches.map(reminderDict),
            "count":     matches.count,
        ])
    }

    private static func reminderDict(_ r: EKReminder) -> [String: Any] {
        [
            "id":          r.calendarItemIdentifier,
            "title":       r.title ?? "",
            "notes":       r.notes ?? "",
            "list":        r.calendar?.title ?? "",
            "isCompleted": r.isCompleted,
            "dueDate":     r.dueDateComponents.flatMap { Calendar.current.date(from: $0).map { iso($0) } } ?? "",
            "priority":    r.priority,
        ]
    }

    private static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }
}
