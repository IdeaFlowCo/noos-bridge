// ChatDB.swift — SQL/decoder layer for ~/Library/Messages/chat.db.
//
// Ported from mac/spike-chat-db/Sources/ChatDBSpike/ChatDB.swift. Uses
// mattt/Madrid's TypedStream decoder for the attributedBody BLOBs.
// Tapbacks (rows with associated_message_guid) filtered by default;
// search uses UNION two-branch (text-LIKE + attributedBody candidates).
//
// Phase 3 partial features carry over: tapback filter on, attributedBody
// post-decode + filter, sort+merge of branches.

import Foundation
import SQLite3
import TypedStream

enum ChatDB {

    // MARK: - SQLite C interop

    /// SQLite "transient" string-bind sentinel.
    static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // MARK: - Mac epoch <-> Unix epoch
    // chat.db dates are nanoseconds since 2001-01-01 00:00 UTC (Cocoa reference).
    static let MAC_EPOCH_OFFSET: Double = 978_307_200

    static func unixSecondsToMacNanos(_ unix: Double) -> Int64 {
        Int64((unix - MAC_EPOCH_OFFSET) * 1e9)
    }

    static func macNanosToISO(_ nanos: Int64) -> String {
        let unix = Double(nanos) / 1e9 + MAC_EPOCH_OFFSET
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date(timeIntervalSince1970: unix))
    }

    // MARK: - Open / close

    enum OpenError: Error {
        case authorizationDenied
        case other(String)
    }

    static let defaultPath: String =
        NSString(string: "~/Library/Messages/chat.db").expandingTildeInPath

    static func open(path: String = defaultPath) throws -> OpaquePointer {
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        if rc != SQLITE_OK {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let db { sqlite3_close(db) }
            if msg.contains("authorization denied") { throw OpenError.authorizationDenied }
            throw OpenError.other(msg)
        }
        return db!
    }

    static func close(_ db: OpaquePointer) {
        sqlite3_close(db)
    }

    // MARK: - attributedBody decoder

    static func decodeAttributedBody(_ data: Data) -> String? {
        // Madrid: Apple's typedstream format (NSAttributedString)
        if let archivables = try? TypedStreamDecoder.decode(data) {
            let joined = archivables
                .compactMap { $0.stringValue }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { return joined }
        }
        // Fallback for older NSKeyedArchiver-encoded blobs (<macOS 13)
        if let attr = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: NSAttributedString.self, from: data),
           !attr.string.isEmpty {
            return attr.string
        }
        if let any = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data),
           let attr = any as? NSAttributedString,
           !attr.string.isEmpty {
            return attr.string
        }
        return nil
    }

    // MARK: - Search

    struct SearchArgs {
        var query: String?
        var sender: String?
        var sinceDays: Int?
        var limit: Int = 20
        var includeTapbacks: Bool = false
        var includeAttributedBodyMatches: Bool = true
    }

    struct MessageRow {
        let id: Int64
        let ts: String
        let isFromMe: Bool
        let sender: String
        let chat: String
        let text: String
        let bodySource: String  // "text" | "attributedBody" | "none"
    }

    static func search(db: OpaquePointer, args: SearchArgs) -> (rows: [MessageRow], queryMs: Int) {
        let started = Date()

        var rowsA = runSingleBranch(db: db, args: args, branch: .text)
        var rowsB: [MessageRow] = []
        if args.query != nil && args.includeAttributedBodyMatches {
            rowsB = runSingleBranch(db: db, args: args, branch: .attributedBodyOnly)
        }

        // Merge + dedupe by ROWID + sort by date desc + take limit
        var seen = Set<Int64>()
        var merged: [MessageRow] = []
        for r in rowsA + rowsB {
            if seen.insert(r.id).inserted { merged.append(r) }
        }
        merged.sort { $0.ts > $1.ts }
        if merged.count > args.limit { merged = Array(merged.prefix(args.limit)) }

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        return (merged, elapsed)
    }

    private enum SearchBranch { case text, attributedBodyOnly }

    private static func runSingleBranch(
        db: OpaquePointer, args: SearchArgs, branch: SearchBranch
    ) -> [MessageRow] {
        var sql = """
        SELECT
          m.ROWID,
          m.date,
          m.text,
          m.attributedBody,
          m.is_from_me,
          h.id AS handle_id,
          c.display_name AS chat_display,
          c.chat_identifier AS chat_ident
        FROM message m
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        LEFT JOIN chat c ON c.ROWID = cmj.chat_id
        WHERE 1=1
        """
        if !args.includeTapbacks {
            sql += " AND (m.associated_message_guid IS NULL OR m.associated_message_guid = '')"
        }
        if args.sender != nil    { sql += " AND h.id = ?" }
        if args.sinceDays != nil { sql += " AND m.date > ?" }

        switch branch {
        case .text:
            if args.query != nil { sql += " AND m.text LIKE ?" }
            sql += " ORDER BY m.date DESC LIMIT \(args.limit)"
        case .attributedBodyOnly:
            sql += " AND (m.text IS NULL OR length(m.text) = 0)"
            sql += " AND m.attributedBody IS NOT NULL"
            sql += " ORDER BY m.date DESC LIMIT \(args.limit * 20)"
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var bindIdx: Int32 = 0
        if let s = args.sender {
            bindIdx += 1
            sqlite3_bind_text(stmt, bindIdx, s, -1, SQLITE_TRANSIENT)
        }
        if let days = args.sinceDays {
            let unix = Date().timeIntervalSince1970 - Double(days * 86400)
            bindIdx += 1
            sqlite3_bind_int64(stmt, bindIdx, unixSecondsToMacNanos(unix))
        }
        if branch == .text, let q = args.query {
            bindIdx += 1
            sqlite3_bind_text(stmt, bindIdx, "%\(q)%", -1, SQLITE_TRANSIENT)
        }

        var rows: [MessageRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowid     = sqlite3_column_int64(stmt, 0)
            let dateNanos = sqlite3_column_int64(stmt, 1)
            let textCol: String? = sqlite3_column_text(stmt, 2).map { String(cString: $0) }

            var bodyText: String? = (textCol?.isEmpty == false) ? textCol : nil
            var bodySource = bodyText != nil ? "text" : "none"
            if bodyText == nil, let blobPtr = sqlite3_column_blob(stmt, 3) {
                let blobLen = sqlite3_column_bytes(stmt, 3)
                if blobLen > 0 {
                    let data = Data(bytes: blobPtr, count: Int(blobLen))
                    if let decoded = decodeAttributedBody(data), !decoded.isEmpty {
                        bodyText = decoded
                        bodySource = "attributedBody"
                    }
                }
            }

            let isFromMe    = sqlite3_column_int(stmt, 4) == 1
            let handleId    = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
            let chatDisplay = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
            let chatIdent   = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""

            let body = bodyText ?? ""
            if let q = args.query, !body.localizedCaseInsensitiveContains(q) { continue }

            rows.append(MessageRow(
                id: rowid,
                ts: macNanosToISO(dateNanos),
                isFromMe: isFromMe,
                sender: isFromMe ? "me" : handleId,
                chat: chatDisplay.isEmpty ? chatIdent : chatDisplay,
                text: body,
                bodySource: bodySource
            ))
            if branch == .text, rows.count >= args.limit { break }
            if branch == .attributedBodyOnly, rows.count >= args.limit { break }
        }
        return rows
    }

    // MARK: Threads (Phase 3)

    struct ChatSummary {
        let chatId: Int64
        let chatIdentifier: String
        let displayName: String
        let serviceName: String
        let lastTs: String
        let lastSnippet: String
        let messageCount: Int
    }

    static func listRecentChats(db: OpaquePointer, limit: Int = 20) -> (chats: [ChatSummary], queryMs: Int) {
        let started = Date()
        let sql = """
        SELECT
          c.ROWID, c.chat_identifier, c.display_name, c.service_name,
          MAX(m.date) AS last_date,
          (SELECT m2.text FROM message m2
             JOIN chat_message_join cmj2 ON cmj2.message_id = m2.ROWID
             WHERE cmj2.chat_id = c.ROWID
               AND m2.text IS NOT NULL AND length(m2.text) > 0
             ORDER BY m2.date DESC LIMIT 1) AS last_snippet,
          COUNT(m.ROWID) AS msg_count
        FROM chat c
        LEFT JOIN chat_message_join cmj ON cmj.chat_id = c.ROWID
        LEFT JOIN message m ON m.ROWID = cmj.message_id
        GROUP BY c.ROWID
        HAVING last_date IS NOT NULL
        ORDER BY last_date DESC
        LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return ([], 0) }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        var rows: [ChatSummary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let chatRowid     = sqlite3_column_int64(stmt, 0)
            let chatIdent     = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let chatDisplay   = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let serviceName   = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            let lastDateNanos = sqlite3_column_int64(stmt, 4)
            let lastSnippet   = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
            let msgCount      = Int(sqlite3_column_int64(stmt, 6))
            rows.append(ChatSummary(
                chatId: chatRowid, chatIdentifier: chatIdent, displayName: chatDisplay,
                serviceName: serviceName, lastTs: macNanosToISO(lastDateNanos),
                lastSnippet: String(lastSnippet.prefix(140)), messageCount: msgCount
            ))
        }
        return (rows, Int(Date().timeIntervalSince(started) * 1000))
    }

    static func getThread(db: OpaquePointer, chatId: Int64, beforeTs: String? = nil, limit: Int = 50) -> (rows: [MessageRow], queryMs: Int) {
        let started = Date()
        var sql = """
        SELECT m.ROWID, m.date, m.text, m.attributedBody, m.is_from_me,
               h.id AS handle_id, c.display_name AS chat_display, c.chat_identifier AS chat_ident
        FROM message m
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        LEFT JOIN chat c ON c.ROWID = cmj.chat_id
        WHERE cmj.chat_id = ?
          AND (m.associated_message_guid IS NULL OR m.associated_message_guid = '')
        """
        if beforeTs != nil { sql += " AND m.date < ?" }
        sql += " ORDER BY m.date DESC LIMIT \(limit)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return ([], 0) }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, chatId)
        if let beforeStr = beforeTs {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: beforeStr) {
                sqlite3_bind_int64(stmt, 2, unixSecondsToMacNanos(d.timeIntervalSince1970))
            }
        }

        var rows: [MessageRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(messageRowFromStmt(stmt!))
        }
        return (rows, Int(Date().timeIntervalSince(started) * 1000))
    }

    static func getMessage(db: OpaquePointer, messageId: Int64) -> MessageRow? {
        let sql = """
        SELECT m.ROWID, m.date, m.text, m.attributedBody, m.is_from_me,
               h.id AS handle_id, c.display_name AS chat_display, c.chat_identifier AS chat_ident
        FROM message m
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        LEFT JOIN chat c ON c.ROWID = cmj.chat_id
        WHERE m.ROWID = ? LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, messageId)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return messageRowFromStmt(stmt!)
    }

    /// Decode the standard 8-column message-row schema we use everywhere into a MessageRow.
    private static func messageRowFromStmt(_ stmt: OpaquePointer) -> MessageRow {
        let rowid     = sqlite3_column_int64(stmt, 0)
        let dateNanos = sqlite3_column_int64(stmt, 1)
        let textCol: String? = sqlite3_column_text(stmt, 2).map { String(cString: $0) }

        var bodyText: String? = (textCol?.isEmpty == false) ? textCol : nil
        var bodySource = bodyText != nil ? "text" : "none"
        if bodyText == nil, let blobPtr = sqlite3_column_blob(stmt, 3) {
            let blobLen = sqlite3_column_bytes(stmt, 3)
            if blobLen > 0 {
                let data = Data(bytes: blobPtr, count: Int(blobLen))
                if let decoded = decodeAttributedBody(data), !decoded.isEmpty {
                    bodyText = decoded
                    bodySource = "attributedBody"
                }
            }
        }

        let isFromMe    = sqlite3_column_int(stmt, 4) == 1
        let handleId    = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
        let chatDisplay = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
        let chatIdent   = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""

        return MessageRow(
            id: rowid, ts: macNanosToISO(dateNanos), isFromMe: isFromMe,
            sender: isFromMe ? "me" : handleId,
            chat: chatDisplay.isEmpty ? chatIdent : chatDisplay,
            text: bodyText ?? "", bodySource: bodySource
        )
    }
}
