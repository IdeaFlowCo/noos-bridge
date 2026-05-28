// AppInfo.swift — bundle metadata helpers shared by the app and services.

import Foundation

enum AppInfo {
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Noos Bridge"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.ideaflow.noos-bridge"
    }

    static var buildChannel: String {
        Bundle.main.object(forInfoDictionaryKey: "BridgeBuildChannel") as? String ?? "production"
    }

    static var isDevelopmentBuild: Bool {
        buildChannel == "dev" || bundleIdentifier.hasSuffix(".dev")
    }

    static var applicationSupportDirectoryName: String {
        isDevelopmentBuild ? "Noos Bridge Dev" : "Noos Bridge"
    }

    static var applicationSupportDirectory: String {
        let home = NSString(string: "~").expandingTildeInPath
        return "\(home)/Library/Application Support/\(applicationSupportDirectoryName)"
    }

    static var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let channelSuffix = isDevelopmentBuild ? " dev" : ""
        return "v\(version) (\(build))\(channelSuffix)"
    }

    static var gitCommit: String {
        Bundle.main.object(forInfoDictionaryKey: "BridgeGitCommit") as? String ?? "local"
    }
}
