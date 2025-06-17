import Foundation

/// A service class for handling URL validation and normalization
class URLService {
    static let shared = URLService()

    private let linkDetectionQueue = DispatchQueue(label: "urlservice.linkdetection", qos: .utility)

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

    /// Extract links from a text string with improved filtering
    func extractLinks(from text: String) -> [URL] {
        return linkDetectionQueue.sync {
            // Remove hashtags to avoid false positives
            let processedText = removeHashtags(from: text)

            let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue)
            let matches =
                detector?.matches(
                    in: processedText,
                    options: [],
                    range: NSRange(location: 0, length: processedText.utf16.count)
                ) ?? []

            return matches.compactMap { match in
                guard let url = match.url else { return nil }

                // Validate and filter the URL
                let validatedURL = validateURL(url)

                // Only allow HTTP/HTTPS
                guard validatedURL.scheme == "http" || validatedURL.scheme == "https" else {
                    return nil
                }

                // Skip hashtags and mentions
                if isHashtagOrMentionURL(validatedURL) {
                    return nil
                }

                return validatedURL
            }
        }
    }

    /// Remove hashtags from text to improve link detection
    private func removeHashtags(from text: String) -> String {
        let hashtagRegex = try? NSRegularExpression(pattern: "#\\w+", options: [])
        guard let regex = hashtagRegex else { return text }

        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: text.utf16.count),
            withTemplate: ""
        )
    }

    /// Check if a URL is likely a hashtag or mention
    func isHashtagOrMentionURL(_ url: URL) -> Bool {
        // Check for custom socialfusion scheme
        if url.scheme == "socialfusion" {
            return url.host == "tag" || url.host == "user"
        }

        let urlString = url.absoluteString.lowercased()
        let path = url.path.lowercased()

        // Check for URLs that start with hashtag or mention symbols
        if urlString.hasPrefix("#") || urlString.hasPrefix("@") {
            return true
        }

        // Check for profile/user URLs
        if path.hasPrefix("/@") || path.hasPrefix("/users/") || path.hasPrefix("/profile/") {
            return true
        }

        // Check for hashtag URLs
        if url.pathComponents.contains("tags") || url.pathComponents.contains("tag")
            || path.contains("/hashtag/")
        {
            return true
        }

        // Check for common hashtag-like domains
        if let host = url.host?.lowercased() {
            let commonHashtagWords = [
                "workingclass", "laborhistory", "genocide", "dictatorship",
                "humanrights", "freespeech", "uprising", "actuallyautistic",
                "germany", "gaza", "mastodon",
            ]
            for word in commonHashtagWords {
                if host == word || host.hasPrefix(word + ".") {
                    return true
                }
            }
        }

        return false
    }

    /// Check if a URL points to a social media post
    func isSocialMediaPostURL(_ url: URL) -> Bool {
        return isBlueskyPostURL(url) || isMastodonPostURL(url)
    }

    /// Check if a URL is valid and safe to make a request to
    func isValidURLForRequest(_ url: URL) -> Bool {
        // Basic validation - ensure URL has a valid scheme and host
        guard let scheme = url.scheme?.lowercased(),
            let host = url.host?.lowercased()
        else {
            return false
        }

        // Only allow HTTP/HTTPS
        guard ["http", "https"].contains(scheme) else {
            return false
        }

        // Block obvious malicious or problematic domains
        let blockedDomains = ["localhost", "127.0.0.1", "0.0.0.0"]
        if blockedDomains.contains(host) {
            return false
        }

        return true
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
        guard let host = url.host?.lowercased() else { return false }

        // Match bsky.app and bsky.social URLs
        let isBlueskyDomain = host.contains("bsky.app") || host.contains("bsky.social")

        // Check if it's a post URL pattern: /profile/{username}/post/{postId}
        let path = url.path
        let isPostURL = path.contains("/profile/") && path.contains("/post/")

        // Don't treat profile-only URLs as post URLs
        if path.contains("/profile/") && !path.contains("/post/") {
            return false
        }

        return isBlueskyDomain && isPostURL
    }

    /// Determines if a URL is a Mastodon post URL
    /// - Parameter url: The URL to check
    /// - Returns: True if the URL is a Mastodon post URL
    func isMastodonPostURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }

        // Check for common Mastodon instances or pattern
        let isMastodonInstance =
            host.contains("mastodon.social") || host.contains("mastodon.online")
            || host.contains("mas.to") || host.contains("mastodon.world")
            || host.contains(".social")

        // Check if it matches Mastodon post URL pattern: /@username/postID
        let path = url.path
        let components = path.split(separator: "/")

        // For Mastodon URLs like /@username/postID, we expect exactly 2 components
        // Don't treat profile-only URLs (just /@username) as post URLs
        if path.contains("/@") && components.count < 2 {
            return false
        }

        // Check if we have the right pattern and last component is numeric (status ID)
        if components.count >= 2 {
            let lastComponent = components.last!
            let isNumericID = lastComponent.allSatisfy { $0.isNumber }
            // Also ensure the first component starts with @
            let hasUsernamePattern = components.first?.hasPrefix("@") == true
            return isMastodonInstance && isNumericID && hasUsernamePattern
        }

        return false
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

    /// Check if URL is a YouTube video
    func isYouTubeURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "youtube.com" || host == "www.youtube.com" || host == "youtu.be"
            || host == "m.youtube.com"
    }

    /// Extract YouTube video ID from various YouTube URL formats
    func extractYouTubeVideoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""

        // Handle youtu.be short URLs
        if host == "youtu.be" {
            let pathComponents = url.pathComponents
            if pathComponents.count > 1 {
                let videoID = pathComponents[1]
                // Remove any query parameters
                return videoID.components(separatedBy: "?").first
            }
        }

        // Handle youtube.com URLs
        if host.contains("youtube.com") {
            // Check for /watch?v= format
            if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            {
                for item in queryItems {
                    if item.name == "v", let value = item.value {
                        return value
                    }
                }
            }

            // Check for /embed/ format
            let path = url.path
            if path.contains("/embed/") {
                let components = path.components(separatedBy: "/embed/")
                if components.count > 1 {
                    return components[1].components(separatedBy: "/").first
                }
            }

            // Check for /v/ format
            if path.contains("/v/") {
                let components = path.components(separatedBy: "/v/")
                if components.count > 1 {
                    return components[1].components(separatedBy: "/").first
                }
            }
        }

        return nil
    }

    /// Get YouTube video thumbnail URL
    func getYouTubeThumbnailURL(videoID: String, quality: YouTubeThumbnailQuality = .high) -> URL? {
        let thumbnailURL: String
        switch quality {
        case .default:
            thumbnailURL = "https://img.youtube.com/vi/\(videoID)/default.jpg"
        case .medium:
            thumbnailURL = "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg"
        case .high:
            thumbnailURL = "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg"
        case .standard:
            thumbnailURL = "https://img.youtube.com/vi/\(videoID)/sddefault.jpg"
        case .maxres:
            thumbnailURL = "https://img.youtube.com/vi/\(videoID)/maxresdefault.jpg"
        }
        return URL(string: thumbnailURL)
    }
}

/// YouTube thumbnail quality options
enum YouTubeThumbnailQuality {
    case `default`  // 120x90
    case medium  // 320x180
    case high  // 480x360
    case standard  // 640x480
    case maxres  // 1280x720
}
