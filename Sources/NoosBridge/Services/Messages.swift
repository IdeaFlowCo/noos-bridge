// Messages.swift — iMessage capability.
//
// Conforms to Service. Reads ~/Library/Messages/chat.db directly via SQLite,
// using mattt/Madrid's TypedStream decoder to recover the ~4% of messages
// whose body lives only in the typedstream-encoded `attributedBody` BLOB.
//
// Permissions: requires Full Disk Access. `isActivated` returns true iff
// we can open `chat.db` for reading. `activate()` opens System Settings
// to the FDA pane (TCC has no programmatic request API for this).
//
// Tools exposed (Phase 2a):
//   - imessage.search
// Phase 3 adds:
//   - imessage.list_recent_chats
//   - imessage.get_thread
//   - imessage.get_message

import Foundation
import SQLite3
import AppKit
import TypedStream

struct MessagesService: Service {
    let id = "imessage"

    var tools: [Tool] {
        [
            imessageSearchTool,
            imessageListRecentChatsTool,
            imessageGetThreadTool,
            imessageGetMessageTool,
        ]
    }

    var isActivated: Bool {
        get async {
            // Cheap probe: try to open chat.db read-only. Returns
            // SQLITE_AUTH or SQLITE_NOTADB if FDA is missing.
            var db: OpaquePointer?
            let rc = sqlite3_open_v2(ChatDB.defaultPath, &db, SQLITE_OPEN_READONLY, nil)
            if let db { sqlite3_close(db) }
            return rc == SQLITE_OK
        }
    }

    func activate() async throws {
        // Open the FDA pane in System Settings. The user has to drag the
        // .app into the list manually — TCC has no API for this.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            await MainActor.run { _ = NSWorkspace.shared.open(url) }
        }
        // We don't poll/await here — the caller will check `isActivated`
        // after the user grants and re-launches (or just retries).
        throw ServiceError.permissionDenied(
            source: id,
            remediation: "Open System Settings → Privacy & Security → Full Disk Access and toggle on Noos Bridge."
        )
    }

    // MARK: - Tool descriptors

    private var imessageSearchTool: Tool {
        Tool(
            name: "imessage.search",
            description: "Search the user's local iMessage history on their Mac. Returns matching messages with sender, chat, timestamp, and text.",
            inputSchema: JSONSchema(
                properties: [
                    "query":     JSONSchemaProperty(type: "string",  description: "Substring to search for in message text (case-insensitive). Optional — omit for most-recent messages."),
                    "sender":    JSONSchemaProperty(type: "string",  description: "Phone number or email of the sender to filter on (e.g. '+15551234567')."),
                    "sinceDays": JSONSchemaProperty(type: "integer", description: "Only return messages from the last N days. Optional.", minimum: 1, maximum: 3650),
                    "limit":     JSONSchemaProperty(type: "integer", description: "Max number of messages to return. Default 20, hard max 100.", minimum: 1, maximum: 100),
                ],
                required: []
            ),
            implementation: { args in
                try Self.runSearch(args: args)
            }
        )
    }

    private var imessageListRecentChatsTool: Tool {
        Tool(
            name: "imessage.list_recent_chats",   // dotted to match spike + bridge wire
            description: "List the user's most recent iMessage / SMS conversations sorted by latest message timestamp.",
            inputSchema: JSONSchema(
                properties: [
                    "limit": JSONSchemaProperty(type: "integer", description: "Max chats to return. Default 20.", minimum: 1, maximum: 100),
                ]
            ),
            implementation: { args in try Self.runListRecentChats(args: args) }
        )
    }

    private var imessageGetThreadTool: Tool {
        Tool(
            name: "imessage.get_thread",
            description: "Retrieve a paginated slice of messages from a single conversation, newest first.",
            inputSchema: JSONSchema(
                properties: [
                    "chatId":   JSONSchemaProperty(type: "integer", description: "Chat ROWID from imessage.list_recent_chats."),
                    "beforeTs": JSONSchemaProperty(type: "string",  description: "ISO 8601; only return messages older than this. Optional."),
                    "limit":    JSONSchemaProperty(type: "integer", description: "Max messages to return. Default 50.", minimum: 1, maximum: 200),
                ],
                required: ["chatId"]
            ),
            implementation: { args in try Self.runGetThread(args: args) }
        )
    }

    private var imessageGetMessageTool: Tool {
        Tool(
            name: "imessage.get_message",
            description: "Get a single message by its messageId.",
            inputSchema: JSONSchema(
                properties: [
                    "messageId": JSONSchemaProperty(type: "integer", description: "Numeric message ROWID."),
                ],
                required: ["messageId"]
            ),
            implementation: { args in try Self.runGetMessage(args: args) }
        )
    }

    // MARK: - Tool implementations

    private static func runSearch(args: [String: AnyDecodable]) throws -> AnyEncodable {
        let query     = stringArg(args, "query")
        let sender    = stringArg(args, "sender")
        let sinceDays = intArg(args, "sinceDays")
        let limit     = min(intArg(args, "limit") ?? 20, 100)

        let db: OpaquePointer
        do {
            db = try ChatDB.open()
        } catch ChatDB.OpenError.authorizationDenied {
            throw ServiceError.permissionDenied(source: "imessage", remediation: "open_settings_full_disk_access")
        } catch {
            throw ServiceError.underlying(error)
        }
        defer { ChatDB.close(db) }

        let searchArgs = ChatDB.SearchArgs(
            query: query, sender: sender, sinceDays: sinceDays, limit: limit
        )
        let (rows, queryMs) = ChatDB.search(db: db, args: searchArgs)
        let dictRows: [[String: Any]] = rows.map { r in
            [
                "id":         r.id,
                "ts":         r.ts,
                "isFromMe":   r.isFromMe,
                "sender":     r.sender,
                "chat":       r.chat,
                "text":       redactOneTimeCodes(r.text),
                "bodySource": r.bodySource,
            ]
        }
        return AnyEncodable([
            "results": dictRows,
            "count":   rows.count,
            "queryMs": queryMs,
        ])
    }

    private static func runListRecentChats(args: [String: AnyDecodable]) throws -> AnyEncodable {
        let limit = intArg(args, "limit") ?? 20
        let db = try openDB()
        defer { ChatDB.close(db) }
        let (chats, queryMs) = ChatDB.listRecentChats(db: db, limit: limit)
        let rows: [[String: Any]] = chats.map { c in
            [
                "chatId": c.chatId,
                "chatIdentifier": c.chatIdentifier,
                "displayName": c.displayName,
                "serviceName": c.serviceName,
                "lastTs": c.lastTs,
                "lastSnippet": redactOneTimeCodes(c.lastSnippet),
                "messageCount": c.messageCount,
            ]
        }
        return AnyEncodable(["chats": rows, "count": chats.count, "queryMs": queryMs])
    }

    private static func runGetThread(args: [String: AnyDecodable]) throws -> AnyEncodable {
        guard let chatIdInt = int64Arg(args, "chatId") else {
            throw ServiceError.notConfigured(source: "imessage", message: "chatId is required")
        }
        let beforeTs = stringArg(args, "beforeTs")
        let limit    = intArg(args, "limit") ?? 50
        let db = try openDB()
        defer { ChatDB.close(db) }
        let (rows, queryMs) = ChatDB.getThread(db: db, chatId: chatIdInt, beforeTs: beforeTs, limit: limit)
        let dictRows: [[String: Any]] = rows.map { r in
            ["id": r.id, "ts": r.ts, "isFromMe": r.isFromMe, "sender": r.sender,
             "chat": r.chat, "text": redactOneTimeCodes(r.text), "bodySource": r.bodySource]
        }
        return AnyEncodable(["messages": dictRows, "count": rows.count, "queryMs": queryMs])
    }

    private static func runGetMessage(args: [String: AnyDecodable]) throws -> AnyEncodable {
        guard let messageId = int64Arg(args, "messageId") else {
            throw ServiceError.notConfigured(source: "imessage", message: "messageId is required")
        }
        let db = try openDB()
        defer { ChatDB.close(db) }
        guard let r = ChatDB.getMessage(db: db, messageId: messageId) else {
            throw ServiceError.notConfigured(source: "imessage", message: "message \(messageId) not found")
        }
        return AnyEncodable([
            "id": r.id, "ts": r.ts, "isFromMe": r.isFromMe, "sender": r.sender,
            "chat": r.chat, "text": redactOneTimeCodes(r.text), "bodySource": r.bodySource,
        ])
    }

    private static func redactOneTimeCodes(_ text: String) -> String {
        var redacted = text
        let keyword = "(?:verification|security|login|sign[- ]?in|auth(?:entication)?|two[- ]?factor|2fa|one[- ]?time|otp|passcode|code)"
        let code = "\\d(?:[ -]?\\d){3,7}"
        let keywordBeforeCode = "(?i)\\b(\(keyword)[^\\n\\d]{0,40})(\(code))\\b"
        let codeBeforeKeyword = "(?i)\\b(\(code))([^\\n]{0,40}\(keyword))\\b"
        redacted = redacted.replacingOccurrences(
            of: keywordBeforeCode,
            with: "$1[redacted code]",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: codeBeforeKeyword,
            with: "[redacted code]$2",
            options: .regularExpression
        )
        return redacted
    }

    private static func openDB() throws -> OpaquePointer {
        do {
            return try ChatDB.open()
        } catch ChatDB.OpenError.authorizationDenied {
            throw ServiceError.permissionDenied(source: "imessage", remediation: "open_settings_full_disk_access")
        } catch {
            throw ServiceError.underlying(error)
        }
    }

    // MARK: - args helpers

    private static func stringArg(_ args: [String: AnyDecodable], _ key: String) -> String? {
        args[key]?.stringValue
    }
    private static func intArg(_ args: [String: AnyDecodable], _ key: String) -> Int? {
        args[key]?.intValue
    }
    private static func int64Arg(_ args: [String: AnyDecodable], _ key: String) -> Int64? {
        if let i = args[key]?.intValue { return Int64(i) }
        return nil
    }
}
