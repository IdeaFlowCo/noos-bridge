// swift-tools-version:5.9
//
// NoosBridge — macOS menubar app that holds a persistent outbound WebSocket
// to an explicitly paired broker and exposes approved local tools such as
// Messages, Calendar, Contacts, and Reminders to a remote agent.
//
// SwiftPM owns dependencies; the scripts in Scripts/ own bundling, signing,
// and notarization. The official IdeaFlow build uses bundle ID
// com.ideaflow.noos-bridge.

import PackageDescription

let package = Package(
    name: "NoosBridge",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NoosBridge", targets: ["NoosBridge"]),
    ],
    dependencies: [
        // mattt/Madrid — typedstream decoder for chat.db's attributedBody BLOBs
        .package(url: "https://github.com/mattt/Madrid", branch: "main"),
        // Sparkle — auto-update framework. Pinned to a stable >1-month-old release.
        // Wired in but not active until distribution pipeline is live.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4"),
    ],
    targets: [
        .executableTarget(
            name: "NoosBridge",
            dependencies: [
                .product(name: "TypedStream", package: "Madrid"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/NoosBridge",
            resources: [
                // App icon + Info.plist additions live here once we add them.
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
