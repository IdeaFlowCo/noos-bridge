// KeychainStorage.swift — store/retrieve the bridge device token in macOS Keychain.

import Foundation
import Security

enum KeychainStorage {
    private static let service = "com.ideaflow.noos-bridge"
    private static let tokenAccount = "device-token"
    private static let userIdAccount = "noos-user-id"

    @discardableResult
    static func setDeviceToken(_ token: String, userId: String?) -> Bool {
        let ok = setString(token, account: tokenAccount)
        if let userId, !userId.isEmpty {
            _ = setString(userId, account: userIdAccount)
        }
        return ok
    }

    static func getDeviceToken() -> String? {
        getString(account: tokenAccount)
    }

    static func getUserId() -> String? {
        getString(account: userIdAccount)
    }

    static func clear() {
        _ = deleteString(account: tokenAccount)
        _ = deleteString(account: userIdAccount)
    }

    private static func setString(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecSuccess { return true }
        if status != errSecItemNotFound {
            fputs("[NoosBridge] keychain update failed for \(account): \(status)\n", stderr)
            return false
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            fputs("[NoosBridge] keychain add failed for \(account): \(addStatus)\n", stderr)
            return false
        }
        return true
    }

    private static func getString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteString(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
