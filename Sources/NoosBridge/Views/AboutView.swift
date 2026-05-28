// AboutView.swift — small "About Noos Bridge" panel.

import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .shadow(radius: 4, y: 2)
            Text(AppInfo.displayName)
                .font(.title2.bold())
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Connects your Mac's local data to the Noos Slack bot.\nNothing leaves your Mac except answers to specific queries.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer(minLength: 0)
            Text("© IdeaFlow, Inc.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    private var version: String {
        AppInfo.versionLabel
    }
}
