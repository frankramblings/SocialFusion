import AppIntents
import Foundation
import UIKit

struct OpenInSocialFusionIntent: AppIntent {
    static var title: LocalizedStringResource = "Open in SocialFusion"
    static var description = IntentDescription(
        "Opens a Mastodon or Bluesky URL in SocialFusion. Supports post URLs, profile URLs, and shortlinks.",
        categoryName: "Navigation"
    )
    static var openAppWhenRun = true

    @Parameter(title: "URL", description: "A Mastodon or Bluesky post or profile URL")
    var url: URL

    @MainActor
    func perform() async throws -> some IntentResult {
        let urlService = URLService.shared

        // Check if it's a recognized social URL
        if urlService.isBlueskyPostURL(url) {
            let components = url.pathComponents.filter { $0 != "/" }
            if components.count >= 4, components[0] == "profile", components[2] == "post" {
                let handle = components[1]
                let rkey = components[3]
                let atUri = "at://\(handle)/app.bsky.feed.post/\(rkey)"
                let encoded = atUri.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rkey
                let deepLink = URL(string: "socialfusion://post/bluesky/\(encoded)")!
                await UIApplication.shared.open(deepLink)
            }
        } else if urlService.isMastodonPostURL(url) || urlService.isFediversePostURL(url) {
            let components = url.pathComponents.filter { $0 != "/" }
            if components.count >= 2, components[0].hasPrefix("@") {
                let statusId = components.last ?? ""
                let deepLink = URL(string: "socialfusion://post/mastodon/\(statusId)")!
                await UIApplication.shared.open(deepLink)
            }
        } else {
            // Check if it looks like a profile URL
            let components = url.pathComponents.filter { $0 != "/" }
            let host = url.host?.lowercased() ?? ""

            if host == "bsky.app", components.count >= 2, components[0] == "profile" {
                let handle = components[1]
                let deepLink = URL(string: "socialfusion://user/bluesky/\(handle)")!
                await UIApplication.shared.open(deepLink)
            } else if components.count >= 1, components[0].hasPrefix("@") {
                let handle = String(components[0].dropFirst())
                let deepLink = URL(string: "socialfusion://user/mastodon/\(handle)")!
                await UIApplication.shared.open(deepLink)
            } else {
                // Fallback: open compose with the URL
                let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url.absoluteString
                let deepLink = URL(string: "socialfusion://compose?url=\(encoded)")!
                await UIApplication.shared.open(deepLink)
            }
        }

        return .result()
    }
}
