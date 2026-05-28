// ContentView.swift — menubar popover content.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var controller: BridgeController
    @Environment(\.openWindow) private var openWindow
    @State private var unlockPassword = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            statusRow
            Divider()
            actions
        }
        .frame(width: 320)
        .padding(.vertical, 8)
    }

    private var header: some View {
        HStack {
            Image(systemName: "circle.dotted")
                .imageScale(.medium)
                .foregroundStyle(.tint)
            Text("Noos Bridge")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(bridgePowerLabel, systemImage: bridgePowerIcon)
                .foregroundStyle(controller.remoteAccessEnabled ? .green : .red)
            Label(connectionLabel, systemImage: connectionIcon)
                .foregroundStyle(connectionColor)
            Label(lockLabel, systemImage: lockIcon)
                .foregroundStyle(.secondary)
            Label(fdaLabel, systemImage: fdaIcon)
                .foregroundStyle(controller.hasFullDiskAccess ? .green : .orange)
            if let err = controller.lastError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            if controller.lock == .locked {
                unlockControls
                Divider().padding(.vertical, 4)
            }

            Button("Open Control Window…") {
                (NSApp.delegate as? AppDelegate)?.presentSettings()
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 6)

            Button(controller.remoteAccessEnabled ? "Turn Bridge Off on This Mac" : "Turn Bridge On on This Mac") {
                controller.setRemoteAccessEnabled(!controller.remoteAccessEnabled)
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 6)

            if !controller.hasDeviceToken {
                Button("Sign in to Noos…") { controller.startSignIn() }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }

            if controller.lock == .unlocked {
                Button("Lock remote queries") { controller.lockNow() }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }

            Divider().padding(.vertical, 4)

            Button("Open Full Disk Access Settings…") { controller.openFullDiskAccessSettings() }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 6)

            Button("Recheck Permissions") { controller.checkFullDiskAccess() }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 6)

            Button("Restart Noos Bridge") {
                controller.restartApp()
            }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 6)

            Divider().padding(.vertical, 4)

            Button("About Noos Bridge…") { openWindow(id: "about") }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 6)

            Button("Sign Out") { controller.signOut() }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .disabled(!controller.hasDeviceToken)

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .keyboardShortcut("q")
        }
    }

    private var unlockControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unlock on this Mac")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField("Remote unlock password", text: $unlockPassword)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(unlock)
                Button("Unlock") { unlock() }
                    .disabled(unlockPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Remote password attempts are verified by this Mac. Noos does not save the password.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func unlock() {
        let password = unlockPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty else { return }
        controller.attemptUnlock(password: password)
        unlockPassword = ""
    }

    // MARK: - State labels

    private var connectionLabel: String {
        switch controller.connection {
        case .offline:           return controller.remoteAccessEnabled ? "Not connected to bridge server" : "Bridge off on this Mac"
        case .connecting:        return "Connecting to bridge server…"
        case .connected:         return "Connected to bridge server as \(controller.hostname)"
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
        case .locked:   return "Remote queries locked"
        case .unlocked: return "Remote queries unlocked for \(controller.idleTimeoutMinutes) min"
        }
    }
    private var lockIcon: String {
        switch controller.lock {
        case .locked:   return "lock.fill"
        case .unlocked: return "lock.open.fill"
        }
    }
    private var fdaLabel: String {
        controller.hasFullDiskAccess ? "Full Disk Access granted" : "Full Disk Access needed for iMessage"
    }
    private var fdaIcon: String {
        controller.hasFullDiskAccess ? "checkmark.shield.fill" : "shield.lefthalf.filled"
    }
    private var bridgePowerLabel: String {
        controller.remoteAccessEnabled ? "Bridge on this Mac" : "Bridge off on this Mac"
    }
    private var bridgePowerIcon: String {
        controller.remoteAccessEnabled ? "antenna.radiowaves.left.and.right" : "power.circle.fill"
    }
}
