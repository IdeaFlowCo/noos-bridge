// BridgeClient.swift — persistent outbound WSS to the Noos cloud broker.
//
// Ported from mac/spike-chat-db/Sources/ChatDBSpike/Bridge.swift, with
// adjustments to dispatch invokes through the Service protocol's tool list
// instead of a hard-coded switch.

import Darwin
import Foundation

@MainActor
protocol BridgeClientDelegate: AnyObject {
    func bridgeClient(_ client: BridgeClient, didChangeConnection state: BridgeConnectionState)
    func bridgeClient(_ client: BridgeClient, didChangeLock locked: Bool)
    func bridgeClient(_ client: BridgeClient, didLog message: String, level: BridgeLogLevel)
}

enum BridgeConnectionState: Equatable {
    case offline
    case connecting
    case connected
    case error(String)
}

enum BridgeLogLevel { case info, warn, error }

final class BridgeClient: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {

    // Configuration
    let url: URL
    let deviceToken: String
    let hostname: String
    let appVersion: String
    let services: [Service]
    let passwordSalt: String?
    let passwordVerifier: String?
    private var remoteUnlockAllowed: Bool
    private var idleTimeoutSeconds: Int
    weak var delegate: (any BridgeClientDelegate)?

    // State
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var isLocked: Bool = true
    private var lastActivityAt: Date = Date()
    private var idleCheckTask: Task<Void, Never>?
    private var runningForever = false

    private let toolMap: [String: (Service, Tool)]

    init(
        url: URL,
        deviceToken: String,
        hostname: String,
        appVersion: String,
        services: [Service],
        passwordSalt: String? = nil,
        passwordVerifier: String? = nil,
        remoteUnlockAllowed: Bool = true,
        idleTimeoutSeconds: Int = 3600,
        delegate: (any BridgeClientDelegate)? = nil
    ) {
        self.url = url
        self.deviceToken = deviceToken
        self.hostname = hostname
        self.appVersion = appVersion
        self.services = services
        self.passwordSalt = passwordSalt
        self.passwordVerifier = passwordVerifier
        self.remoteUnlockAllowed = remoteUnlockAllowed
        self.idleTimeoutSeconds = idleTimeoutSeconds
        self.isLocked = (passwordSalt != nil && passwordVerifier != nil)
        self.delegate = delegate

        var map: [String: (Service, Tool)] = [:]
        for s in services {
            for t in s.tools { map[t.name] = (s, t) }
        }
        self.toolMap = map

        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    // MARK: - Public API

    func runForever() {
        guard !runningForever else { return }
        runningForever = true
        Task.detached { [weak self] in
            await self?.runForeverInternal()
        }
    }

    func stop() {
        runningForever = false
        task?.cancel()
        idleCheckTask?.cancel()
    }

    func attemptUnlock(password: String) async -> Bool {
        guard let salt = passwordSalt, let verifier = passwordVerifier else { return true }
        let matched = BridgePassword.verify(candidate: password, saltHex: salt, verifierHex: verifier)
        if matched {
            isLocked = false
            lastActivityAt = Date()
            try? await send(UnlockFrame())
            await report { d in
                d?.bridgeClient(self, didChangeLock: false)
                d?.bridgeClient(self, didLog: "Bridge unlocked", level: BridgeLogLevel.info)
            }
        }
        return matched
    }

    func lockNow() async {
        isLocked = true
        try? await send(LockFrame())
        await report { d in
            d?.bridgeClient(self, didChangeLock: true)
            d?.bridgeClient(self, didLog: "Bridge locked manually", level: BridgeLogLevel.info)
        }
    }

    func updateIdleTimeout(seconds: Int) {
        idleTimeoutSeconds = max(seconds, 60)
        lastActivityAt = Date()
    }

    func updateRemoteUnlockAllowed(_ allowed: Bool) {
        remoteUnlockAllowed = allowed
        Task { [weak self] in
            guard let self else { return }
            try? await self.send(RemoteUnlockPolicyFrame(allowed: allowed))
            await self.report { d in
                d?.bridgeClient(self, didLog: allowed ? "Remote unlock allowed" : "Remote unlock disabled; local unlock required", level: allowed ? BridgeLogLevel.info : BridgeLogLevel.warn)
            }
        }
    }

    // MARK: - Run loop

    private func runForeverInternal() async {
        var delaySec: UInt64 = 1
        while runningForever {
            await report { d in d?.bridgeClient(self, didChangeConnection: BridgeConnectionState.connecting) }
            do {
                try await runOnce()
                delaySec = 1
            } catch {
                await report { d in
                    d?.bridgeClient(self, didChangeConnection: BridgeConnectionState.error(String(describing: error)))
                    d?.bridgeClient(self, didLog: "run failed: \(error)", level: BridgeLogLevel.warn)
                }
            }
            await report { d in d?.bridgeClient(self, didChangeConnection: BridgeConnectionState.offline) }
            if !runningForever { break }
            try? await Task.sleep(nanoseconds: delaySec * 1_000_000_000)
            delaySec = min(delaySec * 2, 30)
        }
    }

    private func runOnce() async throws {
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()

        let hello = HelloFrame(
            deviceToken: deviceToken,
            appVersion: appVersion,
            capabilities: services.map { $0.id },
            hostname: hostname,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            remoteUnlockAllowed: remoteUnlockAllowed
        )
        try await send(hello)

        if isLocked {
            try await send(LockFrame())
        } else {
            try await send(UnlockFrame())
        }
        await report { d in d?.bridgeClient(self, didChangeConnection: BridgeConnectionState.connected) }

        idleCheckTask?.cancel()
        idleCheckTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                if Task.isCancelled { return }
                self.checkIdleTimeout()
            }
        }
        defer { idleCheckTask?.cancel() }

        while task.closeCode == .invalid {
            let message = try await task.receive()
            try await handle(message: message)
        }
    }

    private func checkIdleTimeout() {
        guard !isLocked else { return }
        guard passwordSalt != nil else { return }
        let elapsed = Date().timeIntervalSince(lastActivityAt)
        if elapsed >= Double(idleTimeoutSeconds) {
            isLocked = true
            Task { [weak self] in
                guard let self else { return }
                try? await self.send(LockFrame())
                await self.report { d in
                    d?.bridgeClient(self, didChangeLock: true)
                    d?.bridgeClient(self, didLog: "Idle timeout — re-locked", level: BridgeLogLevel.info)
                }
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) async throws {
        let data: Data
        switch message {
        case .data(let d):   data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default:    return
        }

        guard let head = try? JSONDecoder().decode(GenericTypeFrame.self, from: data) else { return }

        switch head.type {
        case "ping":
            try await send(PongFrame())

        case "invoke":
            let invoke = try JSONDecoder().decode(InvokeFrame.self, from: data)
            await dispatchInvoke(invoke)

        case "unlock-attempt":
            let attempt = try JSONDecoder().decode(UnlockAttemptFrame.self, from: data)
            await handleUnlockAttempt(attempt)

        case "lock-request":
            await lockNow()

        case "restart-request":
            await handleRestartRequest()

        case "error":
            if let s = String(data: data, encoding: .utf8) {
                await report { d in d?.bridgeClient(self, didLog: "server error: \(s)", level: BridgeLogLevel.warn) }
            }

        default:
            await report { d in d?.bridgeClient(self, didLog: "unhandled frame type: \(head.type)", level: BridgeLogLevel.warn) }
        }
    }

    private func handleRestartRequest() async {
        let appURL = Bundle.main.bundleURL
        await report { d in d?.bridgeClient(self, didLog: "Restart requested by Noos", level: BridgeLogLevel.warn) }
        runningForever = false
        idleCheckTask?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)

        Task.detached {
            try? await Task.sleep(nanoseconds: 400_000_000)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", appURL.path]
            try? process.run()
            exit(0)
        }
    }

    private func dispatchInvoke(_ invoke: InvokeFrame) async {
        if isLocked {
            try? await send(ResultFrame(
                id: invoke.id, ok: false, result: nil,
                error: ResultErrorPayload(
                    code: "bridge_locked",
                    message: "Bridge is locked; unlock it before invoking tools.",
                    remediation: "open_unlock_page"
                )
            ))
            return
        }

        guard let (_, tool) = toolMap[invoke.tool] else {
            try? await send(ResultFrame(
                id: invoke.id, ok: false, result: nil,
                error: ResultErrorPayload(
                    code: "tool_not_implemented",
                    message: "tool '\(invoke.tool)' is not implemented",
                    remediation: nil
                )
            ))
            return
        }

        let started = Date()
        do {
            let result = try await tool.implementation(invoke.args ?? [:])
            lastActivityAt = Date()
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            await report { d in d?.bridgeClient(self, didLog: "\(invoke.tool) → ok in \(elapsedMs)ms", level: BridgeLogLevel.info) }
            try await send(ResultFrame(id: invoke.id, ok: true, result: result, error: nil))
        } catch let err as ServiceError {
            let (code, remediation) = errorCode(from: err)
            await report { d in d?.bridgeClient(self, didLog: "\(invoke.tool) → \(code)", level: BridgeLogLevel.warn) }
            try? await send(ResultFrame(
                id: invoke.id, ok: false, result: nil,
                error: ResultErrorPayload(code: code, message: err.errorDescription ?? "tool_error", remediation: remediation)
            ))
        } catch {
            try? await send(ResultFrame(
                id: invoke.id, ok: false, result: nil,
                error: ResultErrorPayload(code: "internal_error", message: String(describing: error), remediation: nil)
            ))
        }
    }

    private func handleUnlockAttempt(_ attempt: UnlockAttemptFrame) async {
        guard remoteUnlockAllowed else {
            try? await send(UnlockAttemptResultFrame(id: attempt.id, ok: false, reason: "remote_unlock_disabled"))
            await report { d in d?.bridgeClient(self, didLog: "Remote unlock blocked by local policy", level: BridgeLogLevel.warn) }
            return
        }
        guard let salt = passwordSalt, let verifier = passwordVerifier else {
            try? await send(UnlockAttemptResultFrame(id: attempt.id, ok: false, reason: "bridge_password_not_configured"))
            return
        }
        let matched = BridgePassword.verify(candidate: attempt.password, saltHex: salt, verifierHex: verifier)
        if matched {
            isLocked = false
            lastActivityAt = Date()
            try? await send(UnlockAttemptResultFrame(id: attempt.id, ok: true, reason: nil))
            try? await send(UnlockFrame())
            await report { d in
                d?.bridgeClient(self, didChangeLock: false)
                d?.bridgeClient(self, didLog: "Unlock succeeded (server-driven)", level: BridgeLogLevel.info)
            }
        } else {
            try? await send(UnlockAttemptResultFrame(id: attempt.id, ok: false, reason: "incorrect_password"))
            await report { d in d?.bridgeClient(self, didLog: "Unlock failed (wrong password)", level: BridgeLogLevel.warn) }
        }
    }

    // MARK: - Helpers

    private func send<T: Encodable>(_ frame: T) async throws {
        guard let task = task else { return }
        let data = try JSONEncoder().encode(frame)
        try await task.send(.string(String(data: data, encoding: .utf8) ?? ""))
    }

    private func errorCode(from err: ServiceError) -> (String, String?) {
        switch err {
        case .permissionDenied(_, let remediation): return ("permission_denied", remediation)
        case .notConfigured(_, let m):              return ("not_configured", m)
        case .underlying:                           return ("internal_error", nil)
        }
    }

    private func report(_ block: @escaping @MainActor ((any BridgeClientDelegate)?) -> Void) async {
        let d = self.delegate
        await MainActor.run { block(d) }
    }
}
