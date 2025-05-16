import Foundation
import SwiftUI

/// Wrapper for URL handling service
class URLServiceWrapper {
    static let shared = URLServiceWrapper()

    private init() {}

    /// Check if a URL is a Bluesky post URL
    func isBlueskyPostURL(_ url: URL) -> Bool {
        // Simple check for bsky.app domains with at mention pattern
        return url.absoluteString.contains("bsky.app")
            && (url.absoluteString.contains("/profile/") || url.absoluteString.contains("/post/"))
    }

    /// Check if a URL is a Mastodon post URL
    func isMastodonPostURL(_ url: URL) -> Bool {
        // Simple check for common Mastodon domains with status pattern
        return url.path.contains("/status/") || url.absoluteString.contains("@")
    }

    /// Validate and potentially fix malformed URLs
    func validateURL(_ url: URL) -> URL {
        var fixedURL = url

        // Fix URLs with missing schemes
        if url.scheme == nil {
            if let urlWithScheme = URL(string: "https://" + url.absoluteString) {
                fixedURL = urlWithScheme
            }
        }

        return fixedURL
    }
}
