// OAuthHandler.swift — parse the noos-bridge:// auth callback URL.

import Foundation

struct OAuthCallback {
    let token: String
    let userId: String
    let hostname: String?
}

enum OAuthHandler {
    static func parseCallback(_ url: URL) -> OAuthCallback? {
        guard url.scheme == "noos-bridge" else { return nil }
        guard url.host == "auth-callback" || url.path.hasSuffix("auth-callback") else {
            return nil
        }

        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []
        var dict: [String: String] = [:]
        for item in items {
            if let value = item.value {
                dict[item.name] = value
            }
        }

        guard let token = dict["token"], !token.isEmpty,
              let userId = dict["user"] ?? dict["userId"], !userId.isEmpty else {
            return nil
        }

        return OAuthCallback(token: token, userId: userId, hostname: dict["hostname"])
    }

    @MainActor
    static func handle(_ callback: OAuthCallback, controller: BridgeController) {
        KeychainStorage.setDeviceToken(callback.token, userId: callback.userId)
        controller.didReceiveDeviceToken(callback.token, userId: callback.userId)
    }
}
