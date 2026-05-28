// AboutView.swift — small "About Noos Bridge" panel.

import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Noos Bridge")
                .font(.title2.bold())
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Connects your Mac's local data to paired remote agents.\nNothing leaves your Mac except answers to specific queries.")
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
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "v\(v) (\(b))"
    }
}
