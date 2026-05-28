// App.swift — Noos Bridge entry point.
//
// SwiftUI menubar app on macOS 13+ that also behaves as a regular Dock /
// Cmd-Tab app:
//   - setActivationPolicy(.regular) registers it for Dock + app switcher.
//   - LSUIElement is deliberately NOT set in Info.plist; otherwise Launch
//     Services treats us as an "agent" and stops delivering activation
//     events past the cold-start one.
//   - AppDelegate opens the Settings window when the user activates the
//     app (Cmd-Tab, Dock click, Finder double-click on the running app).
//     We do NOT use SwiftUI's `Settings` scene — in a MenuBarExtra-only
//     app it accepts `showSettingsWindow:` but never presents the window.
//     AppDelegate builds an AppKit NSWindow + NSHostingController instead.
//
// First-launch flow (Phase 2):
//   - if no device token in Keychain → show OnboardingView ("Sign in to Noos")
//   - else → show ContentView (status, lock/unlock, source toggles)
//
// Custom URL scheme `noos-bridge://` registered in Info.plist for the OAuth
// callback. SwiftUI's onOpenURL captures the redirect.

import SwiftUI

@main
struct NoosBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = BridgeController()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        MenuBarExtra("Noos Bridge", systemImage: controller.menuBarIconName) {
            ContentView()
                .environmentObject(controller)
        }
        .menuBarExtraStyle(.window)

        // About panel — separate scene so it can be summoned without focusing
        // on Settings.
        Window("About Noos Bridge", id: "about") {
            AboutView()
                .frame(width: 380, height: 220)
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
    }
}

// We don't use SwiftUI's `Settings` scene to surface the window because in a
// MenuBarExtra-only app it accepts the `showSettingsWindow:` action but never
// actually presents a window. Instead we build a normal AppKit window with
// NSHostingController(SettingsView) and manage its lifecycle here.
@inline(__always)
private func dbg(_ msg: String) {
    FileHandle.standardError.write(Data("[NoosBridge] \(msg)\n".utf8))
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hasSeenInitialActivation = false
    private var settingsWindow: NSWindow?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dbg("shouldHandleReopen flag=\(flag)")
        if !flag { presentSettings() }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        let isFirst = !hasSeenInitialActivation
        hasSeenInitialActivation = true
        dbg("didBecomeActive isFirst=\(isFirst) shared=\(BridgeController.shared != nil)")
        presentSettings()
    }

    func presentSettings() {
        dbg("presentSettings settingsWindow=\(settingsWindow != nil)")

        if settingsWindow == nil {
            guard let controller = BridgeController.shared else {
                dbg("presentSettings: BridgeController.shared is nil!")
                return
            }
            let host = NSHostingController(
                rootView: SettingsView()
                    .environmentObject(controller)
                    .frame(minWidth: 480, minHeight: 360)
            )
            let win = NSWindow(contentViewController: host)
            win.title = "Noos Bridge Settings"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 520, height: 400))
            win.center()
            win.isReleasedWhenClosed = false
            settingsWindow = win
            dbg("created settingsWindow")
        }
        if let settingsWindow, settingsWindow.isMiniaturized {
            settingsWindow.deminiaturize(nil)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        dbg("after makeKeyAndOrderFront: visible=\(settingsWindow?.isVisible ?? false)")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let controller = BridgeController.shared else {
            dbg("openURLs: BridgeController.shared is nil")
            return
        }
        for url in urls {
            guard let callback = OAuthHandler.parseCallback(url) else {
                dbg("openURLs: ignored \(url.absoluteString)")
                continue
            }
            OAuthHandler.handle(callback, controller: controller)
            presentSettings()
        }
    }
}
