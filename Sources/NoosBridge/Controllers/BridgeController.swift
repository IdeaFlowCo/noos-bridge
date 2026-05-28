// BridgeController.swift — main app-side controller.
//
// Owns the BridgeClient instance and surfaces its state to SwiftUI.
// Phase 2a: instantiates the client when a device token is available
// (currently from the BRIDGE_DEVICE_TOKEN env var or a config file
// at ~/Library/Application Support/<app name>/device-token.txt).
// Phase 2b will replace those with OAuth + Keychain.

import SwiftUI
import Combine
import Darwin

enum ConnectionState: Equatable {
    case offline           // no token / not yet paired
    case connecting        // WSS opening
    case connected         // hello accepted, waiting for unlock
    case ready             // unlocked, dispatching tools
    case error(String)
}

enum LockState: Equatable {
    case locked
    case unlocked
}

@MainActor
final class BridgeController: ObservableObject, BridgeClientDelegate {
    /// Set in `init`; lets non-SwiftUI code (e.g. AppDelegate) reach the
    /// live instance without plumbing it through the view hierarchy.
    /// There's only one BridgeController per app.
    static private(set) weak var shared: BridgeController?

    @Published var connection: ConnectionState = .offline
    @Published var lock: LockState = .locked
    @Published var hostname: String = Host.current().localizedName ?? "this Mac"
    @Published var lastError: String?
    @Published private(set) var noosUserId: String?
    @Published private(set) var hasDeviceToken: Bool = false
    @Published private(set) var hasFullDiskAccess: Bool = false
    @Published private(set) var fdaLastChecked: Date?
    @Published private(set) var remoteAccessEnabled: Bool = true
    @Published private(set) var remoteUnlockAllowed: Bool = true
    @Published private(set) var idleTimeoutMinutes: Int = 5
    @Published private(set) var logLines: [String] = []   // last ~50 lines for the popover

    private var client: BridgeClient?
    private var passwordSalt: String?
    private var passwordVerifier: String?
    private static let remoteAccessEnabledKey = "NoosBridge.remoteAccessEnabled"
    private static let remoteUnlockAllowedKey = "NoosBridge.remoteUnlockAllowed"
    private static let idleTimeoutMinutesKey = "idleTimeoutMin"

    /// Default broker URL. Override for local testing via BRIDGE_WSS_URL env var.
    static let defaultWssURL = URL(string: "wss://globalbr.ai/api/bridge/connect")!

    private static var configuredWssURL: URL {
        URL(string: ProcessInfo.processInfo.environment["BRIDGE_WSS_URL"] ?? "") ?? defaultWssURL
    }

    private static var configuredAuthURL: URL {
        if let explicit = URL(string: ProcessInfo.processInfo.environment["BRIDGE_AUTH_URL"] ?? "") {
            return explicit
        }

        var components = URLComponents(url: configuredWssURL, resolvingAgainstBaseURL: false)
        components?.scheme = configuredWssURL.scheme == "ws" ? "http" : "https"
        components?.path = "/bridge/auth"
        components?.query = nil
        return components?.url ?? URL(string: "https://globalbr.ai/bridge/auth")!
    }

    var menuBarIconName: String {
        switch (connection, lock) {
        case (.offline, _):          return "circle.slash"
        case (.connecting, _):       return "arrow.triangle.2.circlepath"
        case (.connected, .locked):  return "lock.circle"
        case (.connected, .unlocked): return "circle.dotted"
        case (.ready, .unlocked):    return "circle.fill"
        case (.ready, .locked):      return "lock.circle.fill"
        case (.error, _):            return "exclamationmark.triangle.fill"
        }
    }

    init() {
        Self.shared = self
        if UserDefaults.standard.object(forKey: Self.remoteAccessEnabledKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.remoteAccessEnabledKey)
        }
        if UserDefaults.standard.object(forKey: Self.remoteUnlockAllowedKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.remoteUnlockAllowedKey)
        }
        if UserDefaults.standard.object(forKey: Self.idleTimeoutMinutesKey) == nil {
            UserDefaults.standard.set(5, forKey: Self.idleTimeoutMinutesKey)
        }
        remoteAccessEnabled = UserDefaults.standard.bool(forKey: Self.remoteAccessEnabledKey)
        remoteUnlockAllowed = UserDefaults.standard.bool(forKey: Self.remoteUnlockAllowedKey)
        idleTimeoutMinutes = max(1, UserDefaults.standard.integer(forKey: Self.idleTimeoutMinutesKey))
        // Auto-start: if we have a device token + bridge password configured,
        // open the WSS immediately.
        Task { await self.bootstrapFromEnvOrFiles() }
        Task { @MainActor in self.checkFullDiskAccess() }
    }

    private func bootstrapFromEnvOrFiles() async {
        self.noosUserId = KeychainStorage.getUserId()

        // Token priority: Keychain > env var > ~/Library/Application Support/<app name>/device-token.txt
        let token = readDeviceToken()
        self.hasDeviceToken = token != nil && !(token?.isEmpty ?? true)

        // Bridge password verifier: load from disk if present (will throw if not configured)
        do {
            let p = try BridgePassword.loadOrInstall()   // uses BRIDGE_PASSWORD env if first run
            self.passwordSalt = p.saltHex
            self.passwordVerifier = p.verifierHex
        } catch BridgePassword.LoadError.notConfigured {
            appendLog("No bridge password configured yet — waiting for first-run setup", .info)
        } catch {
            appendLog("Verifier load failed: \(error)", .warn)
        }

        guard let token, !token.isEmpty else {
            appendLog("No device token — sign in to Noos to pair this Mac", .info)
            return
        }
        guard remoteAccessEnabled else {
            appendLog("Bridge is turned off — remote access disabled", .warn)
            connection = .offline
            return
        }
        await startClient(deviceToken: token)
    }

    private func readDeviceToken() -> String? {
        if let keychain = KeychainStorage.getDeviceToken(), !keychain.isEmpty {
            return keychain
        }
        if let env = ProcessInfo.processInfo.environment["BRIDGE_DEVICE_TOKEN"], !env.isEmpty {
            return env
        }
        let path = "\(AppInfo.applicationSupportDirectory)/device-token.txt"
        if let data = try? String(contentsOfFile: path, encoding: .utf8) {
            return data.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func startClient(deviceToken: String) async {
        guard remoteAccessEnabled else {
            appendLog("Bridge start blocked because remote access is off", .warn)
            connection = .offline
            return
        }
        let url = Self.configuredWssURL
        appendLog("Starting WSS to \(url)", .info)

        let services: [Service] = [
            MessagesService(),
            CalendarService(),
            RemindersService(),
            ContactsService(),
            // WhatsApp via embedded whatsmeow lands in Phase 5
        ]

        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"

        let client = BridgeClient(
            url: url,
            deviceToken: deviceToken,
            hostname: hostname,
            appVersion: appVersion,
            services: services,
            passwordSalt: passwordSalt,
            passwordVerifier: passwordVerifier,
            remoteUnlockAllowed: remoteUnlockAllowed,
            idleTimeoutSeconds: idleTimeoutMinutes * 60,
            delegate: self
        )
        self.client = client
        client.runForever()
    }

    // MARK: - User actions

    func startSignIn() {
        var components = URLComponents(url: Self.configuredAuthURL, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: "source", value: "mac-app"))
        items.append(URLQueryItem(name: "hostname", value: hostname))
        components?.queryItems = items

        guard let url = components?.url else {
            lastError = "Couldn't open bridge sign-in URL."
            appendLog("Invalid bridge sign-in URL", .error)
            return
        }
        NSWorkspace.shared.open(url)
        appendLog("Opened bridge sign-in in browser: \(url)", .info)
    }

    func openWebApp() {
        let url = AppInfo.webAppURL
        NSWorkspace.shared.open(url)
        appendLog("Opened Ask My Mac web app: \(url)", .info)
    }

    func didReceiveDeviceToken(_ token: String, userId: String) {
        KeychainStorage.setDeviceToken(token, userId: userId)
        noosUserId = userId
        hasDeviceToken = true
        appendLog("Received device token for \(userId)", .info)
        guard remoteAccessEnabled else {
            appendLog("Token saved; bridge remains off until you re-enable remote access", .warn)
            return
        }
        Task {
            self.client?.stop()
            self.client = nil
            await self.startClient(deviceToken: token)
        }
    }

    func signOut() {
        KeychainStorage.clear()
        client?.stop()
        client = nil
        noosUserId = nil
        hasDeviceToken = false
        connection = .offline
        lock = .locked
        appendLog("Signed out and cleared device token", .info)
    }

    func setRemoteAccessEnabled(_ enabled: Bool) {
        remoteAccessEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.remoteAccessEnabledKey)
        if enabled {
            appendLog("Bridge remote access enabled", .info)
            if let token = readDeviceToken(), !token.isEmpty {
                Task {
                    self.client?.stop()
                    self.client = nil
                    await self.startClient(deviceToken: token)
                }
            }
        } else {
            client?.stop()
            client = nil
            connection = .offline
            lock = .locked
            appendLog("Bridge remote access turned off", .warn)
        }
    }

    func setIdleTimeoutMinutes(_ minutes: Int) {
        let clamped = min(max(minutes, 1), 240)
        idleTimeoutMinutes = clamped
        UserDefaults.standard.set(clamped, forKey: Self.idleTimeoutMinutesKey)
        client?.updateIdleTimeout(seconds: clamped * 60)
        appendLog("Idle re-lock set to \(clamped) min", .info)
    }

    func setRemoteUnlockAllowed(_ allowed: Bool) {
        remoteUnlockAllowed = allowed
        UserDefaults.standard.set(allowed, forKey: Self.remoteUnlockAllowedKey)
        client?.updateRemoteUnlockAllowed(allowed)
        appendLog(allowed ? "Remote unlock allowed" : "Remote unlock disabled; local unlock required", allowed ? .info : .warn)
    }

    func checkFullDiskAccess() {
        let path = ("~/Library/Messages/chat.db" as NSString).expandingTildeInPath
        let fd = open(path, O_RDONLY)
        let granted = fd >= 0
        if granted { close(fd) }
        hasFullDiskAccess = granted
        fdaLastChecked = Date()
        if granted {
            appendLog("Full Disk Access verified", .info)
        } else {
            appendLog("Full Disk Access missing for Messages", .warn)
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
            appendLog("Opened Full Disk Access settings", .info)
        }
    }

    func attemptUnlock(password: String) {
        Task {
            guard let client = self.client else {
                self.lastError = "Bridge not started — sign in first."
                return
            }
            let ok = await client.attemptUnlock(password: password)
            if !ok {
                self.lastError = "Incorrect password."
            } else if self.lastError == "Incorrect password." {
                self.lastError = nil
            }
        }
    }

    func lockNow() {
        Task { await self.client?.lockNow() }
    }

    func restartApp() {
        let appURL = Bundle.main.bundleURL
        appendLog("Restarting Noos Bridge app", .warn)
        client?.stop()
        client = nil
        connection = .offline
        lock = .locked

        Task.detached {
            try? await Task.sleep(nanoseconds: 350_000_000)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", appURL.path]
            try? process.run()
            exit(0)
        }
    }

    // MARK: - BridgeClientDelegate

    nonisolated func bridgeClient(_ client: BridgeClient, didChangeConnection state: BridgeConnectionState) {
        Task { @MainActor in
            switch state {
            case .offline:    self.connection = .offline
            case .connecting: self.connection = .connecting
            case .connected:
                // If we're locked, stay in 'connected' (waiting for unlock).
                // If we're unlocked, jump to 'ready' (connected & accepting tool calls).
                self.connection = (self.lock == .unlocked) ? .ready : .connected
            case .error(let m):
                self.connection = .error(m)
                self.lastError = m
            }
        }
    }

    nonisolated func bridgeClient(_ client: BridgeClient, didChangeLock locked: Bool) {
        Task { @MainActor in
            self.lock = locked ? .locked : .unlocked
            // If we're connected and just got unlocked, move to 'ready'.
            if !locked, case .connected = self.connection {
                self.connection = .ready
            }
            if locked, case .ready = self.connection {
                self.connection = .connected
            }
            if !locked, self.lastError == "Incorrect password." {
                self.lastError = nil
            }
        }
    }

    nonisolated func bridgeClient(_ client: BridgeClient, didLog message: String, level: BridgeLogLevel) {
        Task { @MainActor in self.appendLog(message, level) }
    }

    private func appendLog(_ message: String, _ level: BridgeLogLevel) {
        let prefix: String
        switch level {
        case .info:  prefix = "  "
        case .warn:  prefix = "⚠ "
        case .error: prefix = "✖ "
        }
        let line = "\(timestamp()) \(prefix)\(message)"
        self.logLines.append(line)
        if self.logLines.count > 50 { self.logLines.removeFirst(self.logLines.count - 50) }
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
