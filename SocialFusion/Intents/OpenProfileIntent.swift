import AppIntents
import Foundation
import UIKit

struct OpenProfileIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Profile in SocialFusion"
    static var description = IntentDescription(
        "Opens a user profile in SocialFusion. Accepts a handle, DID, URL, or @user@server format.",
        categoryName: "Navigation"
    )
    static var openAppWhenRun = true

    @Parameter(title: "Identifier", description: "A handle (e.g. @user@mastodon.social), DID, or profile URL")
    var identifier: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to parse as URL first
        if let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http" {
            let host = url.host?.lowercased() ?? ""
            let components = url.pathComponents.filter { $0 != "/" }

            if host == "bsky.app", components.count >= 2, components[0] == "profile" {
                let handle = components[1]
                await UIApplication.shared.open(URL(string: "socialfusion://user/bluesky/\(handle)")!)
                return .result()
            } else if components.count >= 1, components[0].hasPrefix("@") {
                let handle = String(components[0].dropFirst())
                await UIApplication.shared.open(URL(string: "socialfusion://user/mastodon/\(handle)")!)
                return .result()
            }
        }

        // Check for DID (Bluesky)
        if trimmed.hasPrefix("did:") {
            await UIApplication.shared.open(URL(string: "socialfusion://user/bluesky/\(trimmed)")!)
            return .result()
        }

        // Check for @user@server (Mastodon/fediverse)
        var handle = trimmed
        if handle.hasPrefix("@") { handle = String(handle.dropFirst()) }

        if handle.contains("@") {
            // user@server format → Mastodon
            await UIApplication.shared.open(URL(string: "socialfusion://user/mastodon/\(handle)")!)
        } else if handle.contains(".") {
            // Looks like a domain-based handle → Bluesky (e.g. user.bsky.social)
            await UIApplication.shared.open(URL(string: "socialfusion://user/bluesky/\(handle)")!)
        } else {
            // Bare handle — default to Bluesky since Mastodon needs a server
            await UIApplication.shared.open(URL(string: "socialfusion://user/bluesky/\(handle)")!)
        }

        return .result()
    }
}
