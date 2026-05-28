// SettingsView.swift — main app window: status, actions, preferences.

import SwiftUI
import ServiceManagement

private struct ComingSoonSource: Identifiable {
    let id: String
    let connector: String
}

private let comingSoonSources: [ComingSoonSource] = [
    .init(id: "WhatsApp", connector: "Unipile"),
    .init(id: "LinkedIn", connector: "Unipile"),
    .init(id: "Instagram", connector: "Unipile"),
    .init(id: "Messenger", connector: "Unipile"),
    .init(id: "Telegram", connector: "Unipile"),
    .init(id: "X", connector: "Unipile"),
    .init(id: "Gmail", connector: "Google"),
    .init(id: "Outlook", connector: "Microsoft"),
    .init(id: "IMAP", connector: "Mail"),
    .init(id: "Google Calendar", connector: "Google"),
    .init(id: "Outlook Calendar", connector: "Microsoft"),
]

struct SettingsView: View {
    @EnvironmentObject var controller: BridgeController
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @State private var unlockPassword = ""

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            sourcesTab
                .tabItem { Label("Sources", systemImage: "tray.full") }
            advancedTab
                .tabItem { Label("Advanced", systemImage: "wrench.adjustable") }
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("Bridge") {
                Toggle(isOn: Binding(
                    get: { controller.remoteAccessEnabled },
                    set: { controller.setRemoteAccessEnabled($0) }
                )) {
                    Label("Bridge on this Mac", systemImage: "power")
                }
                Text("Turn this off to stop the bridge socket on this Mac. Web and mobile apps cannot turn it back on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Connection") {
                    Label(connectionLabel, systemImage: connectionIcon)
                        .foregroundStyle(connectionColor)
                        .labelStyle(.titleAndIcon)
                }
                LabeledContent("This Mac", value: controller.hostname)
                LabeledContent("Version",
                    value: AppInfo.versionLabel)
                LabeledContent("Channel", value: AppInfo.buildChannel)
                LabeledContent("Commit", value: AppInfo.gitCommit)
                if let userId = controller.noosUserId {
                    LabeledContent("Noos user", value: userId)
                }
                if isSignedOut {
                    Button {
                        controller.startSignIn()
                    } label: {
                        Label("Sign in to Noos…", systemImage: "person.badge.key")
                    }
                } else {
                    Button {
                        controller.signOut()
                    } label: {
                        Label("Sign out", systemImage: "person.crop.circle.badge.xmark")
                    }
                }
                Button {
                    controller.restartApp()
                } label: {
                    Label("Restart \(AppInfo.displayName)", systemImage: "arrow.clockwise.circle")
                }
                if let err = controller.lastError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section("Remote Query Access") {
                LabeledContent("State", value: lockLabel)
                Toggle(isOn: Binding(
                    get: { controller.remoteUnlockAllowed },
                    set: { controller.setRemoteUnlockAllowed($0) }
                )) {
                    Label("Allow web/mobile unlock", systemImage: "iphone.and.arrow.forward")
                }
                Text(controller.remoteUnlockAllowed
                    ? "Default: web and mobile can send a bridge password to this Mac for local verification. Noos does not save it."
                    : "Local-only lock: web and mobile cannot unlock this Mac. Unlock from \(AppInfo.displayName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if controller.lock == .unlocked {
                    Button {
                        controller.lockNow()
                    } label: {
                        Label("Lock remote queries", systemImage: "lock.fill")
                    }
                }
                if controller.lock == .locked {
                    SecureField("Remote unlock password", text: $unlockPassword)
                        .onSubmit(unlock)
                    Button {
                        unlock()
                    } label: {
                        Label("Unlock on this Mac", systemImage: "lock.open.fill")
                    }
                    .disabled(unlockPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("This always unlocks locally on the Mac, even when web/mobile unlock is disabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Stepper("Idle re-lock after \(controller.idleTimeoutMinutes) minutes",
                        value: Binding(
                            get: { controller.idleTimeoutMinutes },
                            set: { controller.setIdleTimeoutMinutes($0) }
                        ),
                        in: 1...240,
                        step: 1)
                Text("The Mac controls whether remote unlock is allowed. Turning the whole Bridge off above is the stronger kill switch and cannot be reversed from web or mobile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Preferences") {
                Toggle("Launch \(AppInfo.displayName) at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { new in
                        do {
                            if new { try SMAppService.mainApp.register() }
                            else   { try SMAppService.mainApp.unregister() }
                        } catch {
                            controller.lastError = "Couldn't update launch-at-login: \(error.localizedDescription)"
                        }
                    }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Sources

    private var sourcesTab: some View {
        Form {
            Section("iMessage") {
                LabeledContent("Full Disk Access") {
                    Label(
                        controller.hasFullDiskAccess ? "Granted" : "Missing",
                        systemImage: controller.hasFullDiskAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(controller.hasFullDiskAccess ? .green : .orange)
                }
                Button {
                    controller.openFullDiskAccessSettings()
                } label: {
                    Label("Open Full Disk Access Settings…", systemImage: "gearshape")
                }
                Button {
                    controller.checkFullDiskAccess()
                } label: {
                    Label("Recheck Full Disk Access", systemImage: "arrow.clockwise")
                }
                Text("\(AppInfo.displayName) needs Full Disk Access to read Messages' local chat.db. macOS requires you to grant this manually in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Native Sources") {
                Toggle("iMessage history", isOn: .constant(true))
                    .disabled(true)
                Toggle("Contacts", isOn: .constant(true))
                    .disabled(true)
                Toggle("Calendar", isOn: .constant(true))
                    .disabled(true)
                Toggle("Reminders", isOn: .constant(true))
                    .disabled(true)
            }
            Section {
                Text("Contacts, Calendar, and Reminders use native macOS permission prompts the first time a remote agent invokes those tools.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(
                header: Text("Coming Soon"),
                footer: Text("These planned sources are visible here so setup status is clear before the connectors are active.")
            ) {
                ForEach(comingSoonSources) { source in
                    LabeledContent(source.id) {
                        HStack(spacing: 8) {
                            Text(source.connector)
                                .foregroundStyle(.secondary)
                            Text("Coming soon")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.tertiary, in: Capsule())
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Advanced

    private var advancedTab: some View {
        Form {
            Section("About") {
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "(unknown)")
                LabeledContent("Version",
                    value: AppInfo.versionLabel)
                LabeledContent("Channel", value: AppInfo.buildChannel)
                LabeledContent("Commit", value: AppInfo.gitCommit)
                LabeledContent("Support folder", value: AppInfo.applicationSupportDirectoryName)
                LabeledContent("Hostname", value: controller.hostname)
            }
            Section("Diagnostics") {
                Button {
                    controller.restartApp()
                } label: {
                    Label("Restart \(AppInfo.displayName)", systemImage: "arrow.clockwise.circle")
                }
                Button("Open system logs") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/var/log"))
                }
            }
            Section("Recent Events") {
                if controller.logLines.isEmpty {
                    Text("No recent Bridge events.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(controller.logLines.suffix(12).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Status helpers (mirrors ContentView so the menubar dropdown and
    // the Settings window agree on labels/colors).

    private var isSignedOut: Bool {
        !controller.hasDeviceToken
    }

    private var connectionLabel: String {
        switch controller.connection {
        case .offline:           return controller.remoteAccessEnabled ? "Not connected to bridge server" : "Bridge off on this Mac"
        case .connecting:        return "Connecting to bridge server…"
        case .connected:         return "Connected — waiting for unlock"
        case .ready:             return "Connected & ready"
        case .error(let m):      return "Connection error: \(m)"
        }
    }
    private var connectionIcon: String {
        switch controller.connection {
        case .offline:    return "circle.slash"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .connected:  return "circle.dotted"
        case .ready:      return "circle.fill"
        case .error:      return "exclamationmark.triangle.fill"
        }
    }
    private var connectionColor: Color {
        switch controller.connection {
        case .ready:      return .green
        case .error:      return .red
        case .offline:    return .secondary
        default:          return .primary
        }
    }
    private var lockLabel: String {
        switch controller.lock {
        case .locked:   return "Locked — remote queries are blocked"
        case .unlocked: return "Unlocked — remote queries are allowed"
        }
    }

    private func unlock() {
        let password = unlockPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty else { return }
        controller.attemptUnlock(password: password)
        unlockPassword = ""
    }
}
