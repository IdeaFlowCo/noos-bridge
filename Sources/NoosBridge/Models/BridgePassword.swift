// BridgePassword.swift — local password verifier for the bridge lock/unlock flow.
//
// v1 (Phase 1, Shape 1): salted SHA-256 hash in
// ~/Library/Application Support/<app name>/state.json (mode 0600).
// Phase 2 upgrades to Argon2id-derived key + Secure Enclave Keychain ACL
// (see noos-uuga.14).
//
// Lifecycle:
//   - First connect: if state.json doesn't exist AND BRIDGE_PASSWORD env
//     var is set, generate fresh salt + verifier and write.
//   - Subsequent connects: state.json wins; env var is ignored.
//   - Reset: delete state.json and reconnect with BRIDGE_PASSWORD set.

import Foundation
import CryptoKit

enum BridgePassword {

    static var stateFilePath: String {
        if let dir = ProcessInfo.processInfo.environment["BRIDGE_STATE_DIR"], !dir.isEmpty {
            return "\(dir)/state.json"
        }
        return "\(AppInfo.applicationSupportDirectory)/state.json"
    }

    private struct State: Codable {
        let version: Int
        let createdAt: String
        let saltHex: String
        let verifierHex: String
    }

    enum LoadError: Error, LocalizedError {
        case notConfigured(String)
        case malformed(String)
        case io(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured(let m), .malformed(let m), .io(let m): return m
            }
        }
    }

    /// Load existing verifier from disk, or install one from the supplied password.
    /// Returns the (saltHex, verifierHex) pair that's now on disk.
    @discardableResult
    static func loadOrInstall(initialPassword: String? = nil) throws -> (saltHex: String, verifierHex: String) {
        let path = stateFilePath
        let fm = FileManager.default

        if fm.fileExists(atPath: path) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let s = try JSONDecoder().decode(State.self, from: data)
                return (s.saltHex, s.verifierHex)
            } catch {
                throw LoadError.malformed("verifier file at \(path) is unreadable: \(error)")
            }
        }

        // Not yet configured — install from the supplied password (or fall back to env var).
        let envPwd = ProcessInfo.processInfo.environment["BRIDGE_PASSWORD"]
        let pwd = initialPassword ?? envPwd
        guard let pwd, !pwd.isEmpty else {
            throw LoadError.notConfigured("""
            No bridge password configured. Set one via the menubar's first-run wizard,
            or pass BRIDGE_PASSWORD in the environment for headless installs.
            Verifier will be written to: \(path)
            """)
        }

        let salt = randomHex(bytes: 16)
        let verifier = sha256Hex(salt: salt, password: pwd)
        let s = State(
            version: 1,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            saltHex: salt,
            verifierHex: verifier
        )
        let dir = (path as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(s)
        try data.write(to: URL(fileURLWithPath: path), options: [.atomic])
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        return (salt, verifier)
    }

    /// Constant-time check whether a candidate password matches the stored verifier.
    static func verify(candidate: String, saltHex: String, verifierHex: String) -> Bool {
        let computed = sha256Hex(salt: saltHex, password: candidate)
        return constantTimeEqual(computed, verifierHex)
    }

    /// Wipe the stored verifier (used by a "reset bridge password" flow).
    static func reset() throws {
        let path = stateFilePath
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: helpers

    private static func sha256Hex(salt: String, password: String) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(salt.utf8))
        hasher.update(data: Data(password.utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func randomHex(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        let rc = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(rc == errSecSuccess, "SecRandomCopyBytes failed: \(rc)")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        if aBytes.count != bBytes.count { return false }
        var diff: UInt8 = 0
        for i in 0..<aBytes.count { diff |= aBytes[i] ^ bBytes[i] }
        return diff == 0
    }
}
