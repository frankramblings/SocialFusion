import Foundation
import UIKit

/// URLService handles URL validation, sanitization and utilities for working with URLs
class URLService {
    static let shared = URLService()

    // A list of domains that cause issues and should be blocked
    private let blockedDomains = [
        "www.threads.net",
        "threads.net",
        // Add other problematic domains here
    ]

    private init() {}

    /// Fully validates and sanitizes a URL, ensuring it's properly formed and not blocked
    func validateURL(_ url: URL) -> URL {
        var fixedURL = url

        // Fix URLs with missing schemes
        if url.scheme == nil {
            if let urlWithScheme = URL(string: "https://" + url.absoluteString) {
                fixedURL = urlWithScheme
            }
        }

        // Check if this domain is blocked
        if let host = fixedURL.host, blockedDomains.contains(host.lowercased()) {
            // Return a special "blocked" URL that won't trigger network requests
            return URL(string: "https://blocked.example.com")!
        }

        // Fix the "www" hostname issue (when host is literally just "www")
        if fixedURL.host == "www" {
            if let correctedURL = URL(string: "https://www." + (fixedURL.path.trimmingPrefix("/")))
            {
                return correctedURL
            }
        }

        // Fix "www." hostname without any TLD (e.g., "www.")
        if fixedURL.host == "www." || fixedURL.absoluteString.contains("://www./") {
            // Return a placeholder since this is invalid
            return URL(string: "https://example.com")!
        }

        // Fix "www/" hostname issue (common mistake in some APIs)
        if let host = fixedURL.host, host.contains("www/") {
            let fixedHost = host.replacingOccurrences(of: "www/", with: "www.")
            var components = URLComponents(url: fixedURL, resolvingAgainstBaseURL: false)
            components?.host = fixedHost
            if let fixedURL = components?.url {
                return fixedURL
            }
        }

        // Check for other invalid host patterns
        if let scheme = fixedURL.scheme,
            let host = fixedURL.host,
            host.contains("/") || host.isEmpty
        {
            // If host contains slashes or is empty, try to reconstruct a valid URL
            return URL(string: "\(scheme)://example.com") ?? fixedURL
        }

        return fixedURL
    }

    /// Check if a URL is valid and safe to make a request to
    func isValidURLForRequest(_ url: URL) -> Bool {
        // Must have a scheme
        guard let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return false
        }

        // Must have a valid host
        guard let host = url.host, !host.isEmpty, !host.contains("/") else {
            return false
        }

        // Check if domain is blocked
        if blockedDomains.contains(host.lowercased()) {
            return false
        }

        return true
    }

    /// Generates a friendly error message for network errors
    func friendlyErrorMessage(for error: Error) -> String {
        let errorDescription = error.localizedDescription

        if errorDescription.contains("App Transport Security") {
            return "Site security issue"
        } else if errorDescription.contains("cancelled") {
            return "Request cancelled"
        } else if errorDescription.contains("network connection") {
            return "Network error"
        } else if errorDescription.contains("hostname could not be found") {
            return "Invalid hostname"
        } else if errorDescription.contains("timed out") {
            return "Request timed out"
        } else if errorDescription.contains("blocked") {
            return "This domain is not supported"
        } else {
            // Truncate long error messages
            let message = errorDescription
            return message.count > 40 ? String(message.prefix(40)) + "..." : message
        }
    }

    /// Create a URLRequest with proper headers and timeout for link preview fetching
    func createLinkPreviewRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0

        // Use a realistic user agent to avoid being blocked
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        // Add other useful headers
        request.setValue(
            "text/html,application/xhtml+xml,application/xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        return request
    }

    /// Check if a URL points to a social media post
    func isSocialMediaPostURL(_ url: URL) -> Bool {
        return isBlueskyPostURL(url) || isMastodonPostURL(url)
    }

    /// Check if URL is a Bluesky post URL
    func isBlueskyPostURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }

        // Match bsky.app and bsky.social URLs
        let isBlueskyDomain = host.contains("bsky.app") || host.contains("bsky.social")

        // Check if it's a post URL pattern: /profile/{username}/post/{postId}
        let path = url.path
        let isPostURL = path.contains("/profile/") && path.contains("/post/")

        return isBlueskyDomain && isPostURL
    }

    /// Check if URL is a Mastodon post URL
    func isMastodonPostURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }

        // Common Mastodon instances or pattern
        let isMastodonInstance =
            host.contains("mastodon.social") || host.contains("mastodon.online")
            || host.contains("mas.to") || host.contains("mastodon.world")
            || host.contains(".social")

        // Match Mastodon post URL pattern: /@username/postID
        let path = url.path
        let isPostURL = path.contains("/@") && path.split(separator: "/").count >= 3

        return isMastodonInstance && isPostURL
    }

    /// Extract a post ID from a Bluesky URL
    func extractBlueskyPostID(_ url: URL) -> String? {
        guard isBlueskyPostURL(url) else { return nil }

        // Extract post ID from path components
        let components = url.path.split(separator: "/")
        if components.count >= 4 && components[components.count - 2] == "post" {
            return String(components[components.count - 1])
        }

        return nil
    }

    /// Extract a post ID from a Mastodon URL
    func extractMastodonPostID(_ url: URL) -> String? {
        guard isMastodonPostURL(url) else { return nil }

        // Extract post ID from path components
        let components = url.path.split(separator: "/")
        if components.count >= 2 {
            return String(components[components.count - 1])
        }

        return nil
    }
}
