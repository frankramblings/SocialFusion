import Foundation

/// A service class for handling URL validation and normalization
class URLService {
    static let shared = URLService()

    private init() {}

    /// Validates and fixes common URL issues
    /// - Parameter urlString: The URL string to validate
    /// - Returns: A validated URL or nil if the URL is invalid and can't be fixed
    func validateURL(_ urlString: String) -> URL? {
        // First, try to create URL as-is
        guard let url = URL(string: urlString) else {
            // If initial creation fails, try percent encoding the string
            let encodedString = urlString.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed)
            return URL(string: encodedString ?? "")
        }

        return validateURL(url)
    }

    /// Validates and fixes common URL issues
    /// - Parameter url: The URL to validate
    /// - Returns: A validated URL
    func validateURL(_ url: URL) -> URL {
        var fixedURL = url

        // Fix URLs with missing schemes
        if url.scheme == nil {
            if let urlWithScheme = URL(string: "https://" + url.absoluteString) {
                fixedURL = urlWithScheme
            }
        }

        // Fix the "www" hostname issue
        if url.host == "www" {
            if let correctedURL = URL(string: "https://www." + (url.path.trimmingPrefix("/"))) {
                return correctedURL
            }
        }

        // Fix "www/" hostname issue
        if let host = url.host, host.contains("www/") {
            let fixedHost = host.replacingOccurrences(of: "www/", with: "www.")
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.host = fixedHost
            if let fixedURL = components?.url {
                return fixedURL
            }
        }

        // Fix duplicate http in URL
        if let host = url.host, host.contains("http://") || host.contains("https://") {
            // Extract the real host by removing the embedded protocol
            let fixedHost = host.replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "https://", with: "")
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.host = fixedHost
            if let fixedURL = components?.url {
                return fixedURL
            }
        }

        return fixedURL
    }

    /// Determines if a URL needs App Transport Security exceptions
    /// - Parameter url: The URL to check
    /// - Returns: True if the URL uses HTTP and might need ATS exceptions
    func needsATSException(_ url: URL) -> Bool {
        return url.scheme?.lowercased() == "http"
    }

    /// Generates a user-friendly error message for URL loading failures
    /// - Parameter error: The error encountered
    /// - Returns: A simplified error message suitable for display to users
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
        } else {
            // Truncate error message if too long
            let message = errorDescription
            return message.count > 40 ? message.prefix(40) + "..." : message
        }
    }

    /// Determines if a URL is a Bluesky post URL
    /// - Parameter url: The URL to check
    /// - Returns: True if the URL is a Bluesky post URL
    func isBlueskyPostURL(_ url: URL) -> Bool {
        guard let host = url.host else { return false }

        // Match bsky.app and bsky.social URLs
        let isBlueskyDomain = host.contains("bsky.app") || host.contains("bsky.social")

        // Check if it's a post URL pattern: /profile/{username}/post/{postId}
        let path = url.path
        let isPostURL = path.contains("/profile/") && path.contains("/post/")

        return isBlueskyDomain && isPostURL
    }

    /// Determines if a URL is a Mastodon post URL
    /// - Parameter url: The URL to check
    /// - Returns: True if the URL is a Mastodon post URL
    func isMastodonPostURL(_ url: URL) -> Bool {
        guard let host = url.host else { return false }

        // Check for common Mastodon instances or pattern
        let isMastodonInstance =
            host.contains("mastodon.social") || host.contains("mastodon.online")
            || host.contains("mas.to") || host.contains("mastodon.world")
            || host.contains(".social")

        // Check if it matches Mastodon post URL pattern: /@username/postID
        let path = url.path
        let isPostURL = path.contains("/@") && path.split(separator: "/").count >= 3

        return isMastodonInstance && isPostURL
    }

    /// Extracts the Bluesky post ID from a URL
    /// - Parameter url: The Bluesky post URL
    /// - Returns: The post ID if available
    func extractBlueskyPostID(_ url: URL) -> String? {
        guard isBlueskyPostURL(url) else { return nil }

        // Extract post ID from path components
        let components = url.path.split(separator: "/")
        if components.count >= 4 && components[components.count - 2] == "post" {
            return String(components[components.count - 1])
        }

        return nil
    }

    /// Extracts the Mastodon post ID from a URL
    /// - Parameter url: The Mastodon post URL
    /// - Returns: The post ID if available
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
