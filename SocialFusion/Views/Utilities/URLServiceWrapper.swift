import Foundation
import SwiftUI

/// Simplified wrapper that delegates to the main URLService
class URLServiceWrapper {
    static let shared = URLServiceWrapper()

    private init() {}

    /// Check if a URL is a Bluesky post URL
    func isBlueskyPostURL(_ url: URL) -> Bool {
        return URLService.shared.isBlueskyPostURL(url)
    }

    /// Check if a URL is a Mastodon post URL
    func isMastodonPostURL(_ url: URL) -> Bool {
        return URLService.shared.isMastodonPostURL(url)
    }

    /// Check if a URL is from any social media platform
    func isSocialMediaURL(_ url: URL) -> Bool {
        return URLService.shared.isSocialMediaPostURL(url)
    }

    /// Extract post ID from a Bluesky URL
    func extractBlueskyPostID(_ url: URL) -> String? {
        return URLService.shared.extractBlueskyPostID(url)
    }

    /// Extract post ID from a Mastodon URL
    func extractMastodonPostID(_ url: URL) -> String? {
        return URLService.shared.extractMastodonPostID(url)
    }

    /// Validate and potentially fix malformed URLs
    func validateURL(_ url: URL) -> URL {
        return URLService.shared.validateURL(url)
    }

    /// Validate and potentially fix malformed URL strings
    func validateURL(_ urlString: String) -> URL? {
        return URLService.shared.validateURL(urlString)
    }
}
