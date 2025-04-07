import Foundation
import UIKit

/// URLService handles URL validation, sanitization and utilities for working with URLs
class URLService {
    static let shared = URLService()

    // MARK: - URL Validation

    /// Validates and fixes common URL issues from a string
    /// - Parameter urlString: The URL string to validate
    /// - Returns: A validated URL or nil if the URL is invalid and can't be fixed
    func validateURL(_ urlString: String) -> URL? {
        // First, try to create URL as-is
        guard var url = URL(string: urlString) else {
            // If initial creation fails, try percent encoding the string
            let encodedString = urlString.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed)
            return URL(string: encodedString ?? "").flatMap { validateURL($0) }
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

        // Check if this domain is blocked
        if let host = fixedURL.host, NetworkConfig.isBlockedDomain(host) {
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

        // Fix duplicate http in URL
        if let host = fixedURL.host, host.contains("http://") || host.contains("https://") {
            // Extract the real host by removing the embedded protocol
            let fixedHost = host.replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "https://", with: "")
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
        return NetworkConfig.shouldAllowRequest(for: url)
    }

    // MARK: - Link Detection

    /// Extract links from a text string
    func extractLinks(from string: String) -> [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(
            in: string, options: [], range: NSRange(location: 0, length: string.utf16.count))

        return matches?.compactMap {
            if let url = $0.url {
                // Validate URLs through our service
                return validateURL(url)
            }
            return nil
        } ?? []
    }

    /// Clean HTML content and extract links
    func processTextContent(_ content: String) -> (String, [URL]) {
        // Clean HTML content
        let cleanedContent = cleanHtmlString(content)

        // Extract links
        let links = extractLinks(from: cleanedContent)

        return (cleanedContent, links)
    }

    /// Enhanced HTML cleanup function with space before links and URL fixes
    func cleanHtmlString(_ html: String) -> String {
        // Replace common HTML entities
        var result =
            html
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        // Remove HTML tags but preserve spacing
        result = result.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression, range: nil)

        // Fix missing spaces before links using regex pattern
        let linkPattern = "(\\S)(https?://\\S+)"
        result = result.replacingOccurrences(
            of: linkPattern, with: "$1 $2", options: .regularExpression, range: nil)

        // Fix for www. links that don't start with http - ensure they have proper format
        // First, add space before www if needed
        let wwwPattern = "(\\S)(www\\.\\S+)"
        result = result.replacingOccurrences(
            of: wwwPattern, with: "$1 $2", options: .regularExpression, range: nil)

        // Fix problematic www/ URLs - replace with www.
        let invalidWwwPattern = "(\\s|^)(www/)([^\\s]+)"
        result = result.replacingOccurrences(
            of: invalidWwwPattern, with: "$1www.$3", options: .regularExpression, range: nil)

        // Fix embedded www/ in the middle of URLs
        let embeddedWwwPattern = "(https?://)(www/)([^\\s]+)"
        result = result.replacingOccurrences(
            of: embeddedWwwPattern, with: "$1www.$3", options: .regularExpression, range: nil)

        // Fix URLs without protocols by adding https://
        let noProtocolPattern = "(\\s|^)(www\\.[^\\s]+)"
        result = result.replacingOccurrences(
            of: noProtocolPattern, with: "$1https://$2", options: .regularExpression, range: nil)

        return result
    }

    // MARK: - Error Handling

    /// Generates a friendly error message for network errors
    func friendlyErrorMessage(for error: Error) -> String {
        if let networkError = error as? NetworkError {
            return networkError.userFriendlyDescription
        }

        // Fall back to general error message processing
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

    // MARK: - Request Creation

    /// Create a URLRequest with proper headers and timeout for link preview fetching
    func createLinkPreviewRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = NetworkConfig.shortTimeout

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

    // MARK: - Social Media URL Detection

    /// Check if a URL points to a social media post
    func isSocialMediaPostURL(_ url: URL) -> Bool {
        return isBlueskyPostURL(url) || isMastodonPostURL(url)
    }

    /// Check if URL is a Bluesky post URL
    func isBlueskyPostURL(_ url: URL) -> Bool {
        guard let host = url.host else { return false }

        // Match bsky.app and bsky.social URLs
        let isBlueskyDomain = host.contains("bsky.app") || host.contains("bsky.social")

        // Check if it's a post URL pattern: /profile/{username}/post/{postId}
        let path = url.path
        let isPostURL = path.contains("/profile/") && path.contains("/post/")

        return isBlueskyDomain && isPostURL
    }

    /// Check if URL is a Mastodon post URL
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

    /// Extract Bluesky post ID from a post URL
    func extractBlueskyPostID(_ url: URL) -> String? {
        guard isBlueskyPostURL(url) else { return nil }

        // Extract post ID from path components
        let components = url.path.split(separator: "/")
        if components.count >= 4 && components[components.count - 2] == "post" {
            return String(components[components.count - 1])
        }

        return nil
    }

    /// Extract Mastodon post ID from a post URL
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
