// Contacts.swift — Apple Contacts capability via Contacts.framework.
//
// Permission: Contacts (TCC popup, no FDA needed).
//
// Tools:
//   - contacts_search — substring match on name / email / phone
//   - contacts_get    — resolve a phone or email to a contact
//
// contacts_get is especially useful as an enrichment for iMessage
// queries — chat.db only has phone numbers and emails; Contacts gives
// us names. The bot can chain: imessage_search → contacts_get → "from
// Sarah" instead of "from +15551234567".

import Foundation
import Contacts

struct ContactsService: Service {
    let id = "contacts"

    private let store = CNContactStore()

    var tools: [Tool] {
        [contactsSearchTool, contactsGetTool]
    }

    var isActivated: Bool {
        get async {
            CNContactStore.authorizationStatus(for: .contacts) == .authorized
        }
    }

    func activate() async throws {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized: return
        case .denied, .restricted:
            throw ServiceError.permissionDenied(
                source: id,
                remediation: "Open System Settings → Privacy & Security → Contacts and toggle on Noos Bridge."
            )
        case .notDetermined:
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                store.requestAccess(for: .contacts) { granted, error in
                    if let error { cont.resume(throwing: ServiceError.underlying(error)); return }
                    if !granted { cont.resume(throwing: ServiceError.permissionDenied(source: "contacts", remediation: nil)); return }
                    cont.resume(returning: ())
                }
            }
        @unknown default:
            throw ServiceError.permissionDenied(source: id, remediation: nil)
        }
    }

    // MARK: - Tool descriptors

    private var contactsSearchTool: Tool {
        Tool(
            name: "contacts.search",
            description: "Search the user's contacts by name (substring, case-insensitive). Returns id, full name, emails, phone numbers, organization.",
            inputSchema: JSONSchema(
                properties: [
                    "query":  JSONSchemaProperty(type: "string",  description: "Name substring to match. Required."),
                    "limit":  JSONSchemaProperty(type: "integer", description: "Max contacts. Default 20.", minimum: 1, maximum: 100),
                ],
                required: ["query"]
            ),
            implementation: { args in try Self.runSearch(store: self.store, args: args) }
        )
    }

    private var contactsGetTool: Tool {
        Tool(
            name: "contacts.get",
            description: "Resolve a single phone number, email, or contact id to a full contact record. Use this to turn iMessage handles like '+15551234567' into names.",
            inputSchema: JSONSchema(
                properties: [
                    "handle":   JSONSchemaProperty(type: "string", description: "Phone number, email, or contact id."),
                ],
                required: ["handle"]
            ),
            implementation: { args in try Self.runGet(store: self.store, args: args) }
        )
    }

    // MARK: - Implementations

    private static let keysToFetch: [CNKeyDescriptor] = [
        CNContactGivenNameKey,
        CNContactFamilyNameKey,
        CNContactOrganizationNameKey,
        CNContactEmailAddressesKey,
        CNContactPhoneNumbersKey,
    ].map { $0 as CNKeyDescriptor }

    private static func runSearch(store: CNContactStore, args: [String: AnyDecodable]) throws -> AnyEncodable {
        guard let query = args["query"]?.stringValue, !query.isEmpty else {
            throw ServiceError.notConfigured(source: "contacts", message: "query is required")
        }
        let limit = args["limit"]?.intValue ?? 20

        let predicate = CNContact.predicateForContacts(matchingName: query)
        let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
        let trimmed = Array(contacts.prefix(limit))
        return AnyEncodable([
            "contacts": trimmed.map(contactDict),
            "count":    trimmed.count,
        ])
    }

    private static func runGet(store: CNContactStore, args: [String: AnyDecodable]) throws -> AnyEncodable {
        guard let handle = args["handle"]?.stringValue, !handle.isEmpty else {
            throw ServiceError.notConfigured(source: "contacts", message: "handle is required")
        }

        // Heuristic: if handle contains '@', treat as email; if starts with + or digit, treat as phone; else try id.
        var matches: [CNContact] = []
        if handle.contains("@") {
            let pred = CNContact.predicateForContacts(matchingEmailAddress: handle)
            matches = try store.unifiedContacts(matching: pred, keysToFetch: keysToFetch)
        } else if handle.first.map({ $0.isNumber || $0 == "+" }) ?? false {
            let phoneNumber = CNPhoneNumber(stringValue: handle)
            let pred = CNContact.predicateForContacts(matching: phoneNumber)
            matches = try store.unifiedContacts(matching: pred, keysToFetch: keysToFetch)
        } else {
            // Fall back to identifier
            if let c = try? store.unifiedContact(withIdentifier: handle, keysToFetch: keysToFetch) {
                matches = [c]
            }
        }

        return AnyEncodable([
            "contacts": matches.map(contactDict),
            "count":    matches.count,
        ])
    }

    private static func contactDict(_ c: CNContact) -> [String: Any] {
        [
            "id":           c.identifier,
            "givenName":    c.givenName,
            "familyName":   c.familyName,
            "fullName":     [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " "),
            "organization": c.organizationName,
            "emails":       c.emailAddresses.map { $0.value as String },
            "phones":       c.phoneNumbers.map { $0.value.stringValue },
        ]
    }
}
