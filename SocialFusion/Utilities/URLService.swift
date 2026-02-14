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

            let results = matches.compactMap { match -> URL? in
                guard let url = match.url else {
                    return nil
                }

                // Clean up the URL to remove trailing punctuation like "-", ".", etc.
                let cleanedURL = cleanURLFromTrailingPunctuation(url)

                // Validate and filter the URL
                let validatedURL = validateURL(cleanedURL)

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

            // Deduplicate URLs while preserving order
            var seen = Set<String>()
            var uniqueResults = [URL]()
            for url in results {
                let urlString = url.absoluteString.lowercased().trimmingCharacters(
                    in: CharacterSet(charactersIn: "/"))
                if !seen.contains(urlString) {
                    seen.insert(urlString)
                    uniqueResults.append(url)
                }
            }

            return uniqueResults
        }
    }

    /// Clean URLs by removing trailing punctuation that shouldn't be part of the URL
    private func cleanURLFromTrailingPunctuation(_ url: URL) -> URL {
        let urlString = url.absoluteString

        // Define characters that shouldn't be at the end of URLs
        let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?-()[]{}\"'")

        // Remove trailing punctuation
        var cleanedString = urlString
        while !cleanedString.isEmpty
            && cleanedString.last?.unicodeScalars.allSatisfy(trailingPunctuation.contains) == true
        {
            cleanedString.removeLast()
        }

        // Return cleaned URL or original if cleaning failed
        return URL(string: cleanedString) ?? url
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

    /// Check if a URL is likely a hashtag or mention (NOT a post URL)
    func isHashtagOrMentionURL(_ url: URL) -> Bool {
        // Check for custom socialfusion scheme
        if url.scheme == "socialfusion" {
            return url.host == "tag" || url.host == "user"
        }

        let urlString = url.absoluteString.lowercased()
        let path = url.path.lowercased()
        let pathComponents = path.split(separator: "/").map(String.init)

        // Check for URLs that start with hashtag or mention symbols
        if urlString.hasPrefix("#") || urlString.hasPrefix("@") {
            return true
        }

        // CRITICAL: Check for profile/user URLs - but NOT post URLs!
        // Mastodon post URLs: /@username/postid (has at least 2 path components after @)
        // Mastodon profile URLs: /@username (just 1 path component)
        // We need to distinguish between them!
        if path.hasPrefix("/@") {
            // If there's only the @username component (or @username/ with nothing after),
            // it's a profile URL. If there's more (like a post ID), it might be a post.
            // Profile: /@username → pathComponents = ["@username"]
            // Post: /@username/123456 → pathComponents = ["@username", "123456"]
            if pathComponents.count == 1 {
                // Just /@username - this is a profile/mention
                return true
            }
            // If count > 1, check if the second component looks like a post ID (numeric)
            if pathComponents.count >= 2 {
                let potentialPostID = pathComponents[1]
                // If it's numeric, this is likely a post URL, NOT a mention
                if potentialPostID.allSatisfy({ $0.isNumber }) && potentialPostID.count > 0 {
                    return false  // This is a post URL, not a mention!
                }
            }
            // Otherwise, treat as a mention
            return true
        }

        // Check /users/username/statuses/id - this is a POST, not a mention
        if path.hasPrefix("/users/") && path.contains("/statuses/") {
            return false  // This is a post URL
        }

        // Check for plain /users/username (no /statuses/) - this is a profile
        if path.hasPrefix("/users/") && !path.contains("/statuses/") {
            return true
        }

        // Check for /profile/ URLs - but distinguish posts from profiles
        // Bluesky: /profile/user/post/postid is a post
        if path.hasPrefix("/profile/") {
            if path.contains("/post/") {
                return false  // This is a Bluesky post URL
            }
            // Otherwise it's just a profile
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
        return isBlueskyPostURL(url) || isFediversePostURL(url)
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

        // Check for AT Protocol URIs (at://did:plc:xxx/app.bsky.feed.post/xxx)
        if url.scheme == "at" {
            let uriString = url.absoluteString.lowercased()
            if uriString.contains("/app.bsky.feed.post/") {
                return true
            }
        }

        // Check if it's a post URL pattern: /profile/{username}/post/{postId}
        let path = url.path
        let isPostURL = path.contains("/profile/") && path.contains("/post/")

        // Don't treat profile-only URLs as post URLs
        if path.contains("/profile/") && !path.contains("/post/") {
            return false
        }

        // Also check for handle.bsky.social/post/postid format
        if host.contains("bsky.social") && path.contains("/post/") {
            let components = path.split(separator: "/")
            if components.contains("post") {
                return true
            }
        }

        return isBlueskyDomain && isPostURL
    }

    /// Determines if a URL is a Mastodon post URL
    /// Uses pattern-based detection rather than hardcoded server lists
    /// - Parameter url: The URL to check
    /// - Returns: True if the URL is a Mastodon post URL
    func isMastodonPostURL(_ url: URL) -> Bool {
        // Delegate to the more comprehensive fediverse detection
        // which uses pattern matching rather than hardcoded domain lists
        return isFediversePostURL(url)
    }

    /// Determines if a URL is a Fediverse post URL (Mastodon, Misskey, Firefish, Calckey, Pleroma, Akkoma, GoToSocial, Pixelfed, etc)
    /// Uses pattern-based detection to identify post URLs without relying on hardcoded server lists
    /// - Parameter url: The URL to check
    /// - Returns: True if the URL is a Fediverse post URL
    func isFediversePostURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let path = url.path
        let pathLowercased = path.lowercased()
        let components = path.split(separator: "/").map(String.init)

        // Exclude known non-fediverse domains that might have similar URL patterns
        let excludedDomains = ["twitter.com", "x.com", "facebook.com", "instagram.com",
                               "linkedin.com", "tiktok.com", "youtube.com", "youtu.be",
                               "reddit.com", "threads.net", "bsky.app", "bsky.social"]
        if excludedDomains.contains(where: { host.contains($0) }) {
            return false
        }

        // === MASTODON-STYLE PATTERNS ===

        // Pattern 1: /@username/postID (numeric ID) - Most common Mastodon pattern
        // Works for: Mastodon, GoToSocial, Hometown, and most Mastodon forks
        if path.contains("/@") && components.count >= 2 {
            let lastComponent = components.last!
            // Check if last component is numeric (status ID)
            let isNumericID = lastComponent.allSatisfy { $0.isNumber }
            // Check if any component starts with @ (username)
            let hasUsernamePattern = components.contains { $0.hasPrefix("@") }
            // Don't treat profile-only URLs as post URLs
            if isNumericID && hasUsernamePattern && lastComponent.count > 0 {
                return true
            }
        }

        // Pattern 2: /users/username/statuses/postID - ActivityPub canonical URL
        // Works for: Mastodon, GoToSocial, and most ActivityPub implementations
        if pathLowercased.contains("/users/") && pathLowercased.contains("/statuses/") {
            if let statusesIdx = components.firstIndex(where: { $0.lowercased() == "statuses" }),
               statusesIdx + 1 < components.count {
                let postID = components[statusesIdx + 1]
                if postID.allSatisfy({ $0.isNumber }) && postID.count > 0 {
                    return true
                }
            }
        }

        // Pattern 3: /statuses/postID - Some instances use this simpler format
        if pathLowercased.hasPrefix("/statuses/") && components.count >= 2 {
            if let idx = components.firstIndex(where: { $0.lowercased() == "statuses" }),
               idx + 1 < components.count {
                let postID = components[idx + 1]
                if postID.allSatisfy({ $0.isNumber }) && postID.count > 0 {
                    return true
                }
            }
        }

        // === MISSKEY/FIREFISH/CALCKEY/SHARKEY PATTERNS ===

        // Pattern 4: /notes/noteID - Misskey and forks
        if pathLowercased.contains("/notes/") && components.count >= 2 {
            if let idx = components.firstIndex(where: { $0.lowercased() == "notes" }),
               idx + 1 < components.count {
                let noteID = components[idx + 1]
                // Note IDs are typically alphanumeric (not UUIDs, but shorter random strings)
                // Misskey uses ~10 char alphanumeric IDs
                if noteID.count >= 8 && noteID.allSatisfy({ $0.isLetter || $0.isNumber }) {
                    return true
                }
            }
        }

        // === PLEROMA/AKKOMA PATTERNS ===

        // Pattern 5: /objects/objectID - Pleroma/Akkoma ActivityPub objects
        if pathLowercased.contains("/objects/") && components.count >= 2 {
            if let idx = components.firstIndex(where: { $0.lowercased() == "objects" }),
               idx + 1 < components.count {
                let objectID = components[idx + 1]
                // Object IDs are typically UUIDs
                if objectID.count > 10 { return true }
            }
        }

        // Pattern 6: /notice/noticeID - Pleroma/Akkoma notice URLs
        if pathLowercased.contains("/notice/") && components.count >= 2 {
            if let idx = components.firstIndex(where: { $0.lowercased() == "notice" }),
               idx + 1 < components.count {
                let noticeID = components[idx + 1]
                // Notice IDs can be alphanumeric
                if noticeID.count >= 8 && noticeID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) {
                    return true
                }
            }
        }

        // === FRIENDICA PATTERNS ===

        // Pattern 7: /display/username/postID - Friendica
        if pathLowercased.contains("/display/") && components.count >= 3 {
            if let displayIdx = components.firstIndex(where: { $0.lowercased() == "display" }),
               displayIdx + 2 < components.count {
                let postID = components[displayIdx + 2]
                if postID.allSatisfy({ $0.isNumber }) && postID.count > 0 {
                    return true
                }
            }
        }

        // Pattern 8: /display/GUID - Friendica GUID-based URLs
        if pathLowercased.hasPrefix("/display/") && components.count == 2 {
            let guid = components[1]
            // Friendica GUIDs are typically long alphanumeric strings or UUIDs
            if guid.count > 20 {
                return true
            }
        }

        // === PIXELFED PATTERNS ===

        // Pattern 9: /p/username/postID - Pixelfed
        if pathLowercased.contains("/p/") && components.count >= 3 {
            if let pIdx = components.firstIndex(where: { $0.lowercased() == "p" }),
               pIdx + 2 < components.count {
                let postID = components[pIdx + 2]
                if postID.allSatisfy({ $0.isNumber }) && postID.count > 0 {
                    return true
                }
            }
        }

        // Pattern 10: /i/web/post/postID - Pixelfed web interface
        if pathLowercased.contains("/i/web/post/") {
            if let postIdx = components.firstIndex(where: { $0.lowercased() == "post" }),
               postIdx + 1 < components.count {
                let postID = components[postIdx + 1]
                if postID.allSatisfy({ $0.isNumber }) && postID.count > 0 {
                    return true
                }
            }
        }

        // === LEMMY PATTERNS ===

        // Pattern 11: /post/postID - Lemmy posts
        if pathLowercased.hasPrefix("/post/") && components.count >= 2 {
            let postID = components[1]
            if postID.allSatisfy({ $0.isNumber }) && postID.count > 0 {
                return true
            }
        }

        // Pattern 12: /comment/commentID - Lemmy comments
        if pathLowercased.hasPrefix("/comment/") && components.count >= 2 {
            let commentID = components[1]
            if commentID.allSatisfy({ $0.isNumber }) && commentID.count > 0 {
                return true
            }
        }

        // === GOTOSOCIAL PATTERNS ===
        // GoToSocial typically uses Mastodon-compatible URLs, but also supports:

        // Pattern 13: /@username/statuses/statusID - GoToSocial canonical
        if path.contains("/@") && pathLowercased.contains("/statuses/") {
            if let statusesIdx = components.firstIndex(where: { $0.lowercased() == "statuses" }),
               statusesIdx + 1 < components.count {
                let statusID = components[statusesIdx + 1]
                // GoToSocial uses ULID format (26 alphanumeric chars)
                if statusID.count >= 20 && statusID.allSatisfy({ $0.isLetter || $0.isNumber }) {
                    return true
                }
            }
        }

        // === HUBZILLA/STREAMS PATTERNS ===

        // Pattern 14: /item/itemID - Hubzilla/Streams
        if pathLowercased.hasPrefix("/item/") && components.count >= 2 {
            let itemID = components[1]
            // Item IDs can be GUIDs or numeric
            if itemID.count > 5 {
                return true
            }
        }

        // === GENERIC ACTIVITYPUB PATTERNS ===

        // Pattern 15: /activities/UUID - Generic ActivityPub activity URLs
        if pathLowercased.contains("/activities/") && components.count >= 2 {
            if let idx = components.firstIndex(where: { $0.lowercased() == "activities" }),
               idx + 1 < components.count {
                let activityID = components[idx + 1]
                // ActivityPub IDs are typically UUIDs
                if activityID.count > 20 {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Quote Post Detection

    /// Extracts a quoted post URL from "RE:" prefix convention used by some Mastodon clients
    /// Format: "RE: https://server.social/@user/123456789" at the start of post content
    /// - Parameter text: The post content text (plain text, not HTML)
    /// - Returns: The extracted URL if found, nil otherwise
    func extractQuoteURLFromREPrefix(in text: String) -> URL? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Early exit for empty or very short text
        guard trimmedText.count >= 3 else { return nil }

        // Check for various RE: prefix formats (case insensitive)
        // Patterns: "RE:", "Re:", "re:", "RE ", "Re ", etc.
        let rePrefixPatterns = [
            "^RE:\\s*",      // RE: with optional space
            "^Re:\\s*",      // Re: with optional space
            "^re:\\s*",      // re: with optional space
            "^RT\\s+@",      // RT @user format (retweet style, less common in fediverse)
        ]

        for pattern in rePrefixPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: trimmedText, options: [], range: NSRange(location: 0, length: trimmedText.utf16.count)) {
                // Found RE: prefix, now extract the URL that follows
                // Convert NSRange to String.Index safely using UTF-16 view
                let utf16View = trimmedText.utf16
                guard let startIndex = utf16View.index(utf16View.startIndex, offsetBy: match.range.location + match.range.length, limitedBy: utf16View.endIndex),
                      let stringIndex = String.Index(startIndex, within: trimmedText) else {
                    continue
                }
                let afterPrefix = String(trimmedText[stringIndex...])

                // Extract the first URL from the text after the prefix
                if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
                   let urlMatch = detector.firstMatch(in: afterPrefix, options: [], range: NSRange(location: 0, length: afterPrefix.utf16.count)),
                   let url = urlMatch.url {
                    // Verify it's a fediverse or Bluesky post URL
                    if isSocialMediaPostURL(url) {
                        return url
                    }
                }
            }
        }

        return nil
    }

    /// Extracts URLs from HTML anchor tag href attributes
    /// This is important for Mastodon content where links are in <a href="..."> tags
    /// - Parameter html: The raw HTML content
    /// - Returns: Array of URLs found in href attributes
    func extractURLsFromHTML(_ html: String) -> [URL] {
        var urls: [URL] = []
        
        // Pattern to match href attributes: href="url" or href='url'
        let hrefPattern = #"href\s*=\s*["']([^"']+)["']"#
        
        guard let regex = try? NSRegularExpression(pattern: hrefPattern, options: [.caseInsensitive]) else {
            return urls
        }
        
        let nsString = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let urlRange = match.range(at: 1)
            guard urlRange.location != NSNotFound else { continue }
            
            let urlString = nsString.substring(with: urlRange)
            // Decode HTML entities in URL
            let decodedURLString = urlString
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
            
            if let url = URL(string: decodedURLString) {
                // Validate and skip hashtag/mention URLs
                guard url.scheme == "http" || url.scheme == "https" else { continue }
                if !isHashtagOrMentionURL(url) {
                    urls.append(url)
                }
            }
        }
        
        // Deduplicate while preserving order
        var seen = Set<String>()
        var uniqueURLs: [URL] = []
        for url in urls {
            let normalized = url.absoluteString.lowercased()
            if !seen.contains(normalized) {
                seen.insert(normalized)
                uniqueURLs.append(url)
            }
        }
        
        return uniqueURLs
    }

    /// Extracts all potential quote post URLs from text content
    /// Checks for RE: prefix convention and also scans for fediverse/Bluesky post URLs
    /// - Parameter text: The post content text (plain text, not HTML)
    /// - Parameter rawHTML: Optional raw HTML to also extract URLs from href attributes
    /// - Returns: Array of URLs that appear to be quote references
    func extractQuotePostURLs(from text: String, rawHTML: String? = nil) -> [URL] {
        var quoteURLs: [URL] = []

        // First, check for RE: prefix convention (highest priority)
        if let reQuoteURL = extractQuoteURLFromREPrefix(in: text) {
            quoteURLs.append(reQuoteURL)
        }

        // Extract links from plain text
        var allLinks = extractLinks(from: text)
        
        // Also extract URLs from HTML href attributes if provided
        // This catches URLs that are in anchor tags but not visible as plain text
        if let html = rawHTML, !html.isEmpty {
            let htmlLinks = extractURLsFromHTML(html)
            for link in htmlLinks where !allLinks.contains(link) {
                allLinks.append(link)
            }
        }
        
        for link in allLinks {
            if (isBlueskyPostURL(link) || isFediversePostURL(link)) && !quoteURLs.contains(link) {
                quoteURLs.append(link)
            }
        }

        return quoteURLs
    }

    /// Extracts quote URLs with their associated text patterns for removal from content
    /// This includes RE: prefixes and standalone quote URLs that will be rendered as cards
    /// - Parameter text: The post content text (plain text, not HTML)
    /// - Parameter rawHTML: Optional raw HTML to extract URLs from href attributes
    /// - Returns: Array of tuples containing the URL and the full text pattern to remove
    func extractQuoteURLsWithTextPatterns(from text: String, rawHTML: String? = nil) -> [(url: URL, pattern: String)] {
        var patterns: [(url: URL, pattern: String)] = []

        // First, check for RE: prefix convention (highest priority)
        if let reQuoteURL = extractQuoteURLFromREPrefix(in: text) {
            // Extract the full RE: prefix pattern
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check for various RE: prefix formats (case insensitive)
            let rePrefixPatterns = [
                "^RE:\\s*",      // RE: with optional space
                "^Re:\\s*",      // Re: with optional space  
                "^re:\\s*",      // re: with optional space
                "^RT\\s+@",      // RT @user format (retweet style, less common in fediverse)
            ]

            for patternStr in rePrefixPatterns {
                if let regex = try? NSRegularExpression(pattern: patternStr, options: []),
                   let match = regex.firstMatch(in: trimmedText, options: [], range: NSRange(location: 0, length: trimmedText.utf16.count)) {
                    // Found RE: prefix, extract the full pattern including URL
                    let utf16View = trimmedText.utf16
                    guard let startIndex = utf16View.index(utf16View.startIndex, offsetBy: match.range.location, limitedBy: utf16View.endIndex),
                          let stringIndex = String.Index(startIndex, within: trimmedText) else {
                        continue
                    }
                    
                    // Extract text from start to end of URL
                    let afterPrefix = String(trimmedText[stringIndex...])
                    
                    // Extract the first URL from the text after the prefix
                    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
                       let urlMatch = detector.firstMatch(in: afterPrefix, options: [], range: NSRange(location: 0, length: afterPrefix.utf16.count)),
                       let url = urlMatch.url {
                        
                        // Get the full text up to and including the URL
                        let urlText = afterPrefix[..<afterPrefix.index(afterPrefix.startIndex, offsetBy: urlMatch.range.length)]
                        let fullPattern = String(trimmedText.prefix(urlText.count + match.range.length))
                        
                        patterns.append((url: url, pattern: fullPattern))
                        break
                    }
                }
            }
        }

        // Extract links from plain text and HTML
        var allLinks = extractLinks(from: text)
        
        // Also extract URLs from HTML href attributes if provided
        if let html = rawHTML, !html.isEmpty {
            let htmlLinks = extractURLsFromHTML(html)
            for link in htmlLinks where !allLinks.contains(link) {
                allLinks.append(link)
            }
        }
        
        // For standalone quote URLs (without RE: prefix), we need to identify them
        // These are social media post URLs that will be rendered as quote cards
        for link in allLinks where !patterns.contains(where: { $0.url == link }) {
            if isBlueskyPostURL(link) || isFediversePostURL(link) {
                // For standalone URLs, the pattern is just the URL itself
                let urlString = link.absoluteString
                patterns.append((url: link, pattern: urlString))
            }
        }

        return patterns
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

    /// Check if a URL is from a Mastodon instance (for media URLs)
    func isMastodonMediaURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }

        // Check for common Mastodon instance patterns
        // Mastodon media URLs typically have paths like /media_attachments/ or /files/
        let path = url.path.lowercased()
        let isMediaPath =
            path.contains("/media_attachments/") || path.contains("/files/")
            || path.contains("/cache/")

        // Check for Mastodon instance domains (common patterns)
        let isMastodonInstance =
            host.contains("mastodon") || host.contains(".social") || host.contains("mas.to")
            || host.contains("mstdn") || host.contains("fediverse")

        return isMastodonInstance && isMediaPath
    }

    /// Check if URL is a direct GIF file URL
    func isGIFURL(_ url: URL) -> Bool {
        let urlString = url.absoluteString.lowercased()
        let host = url.host?.lowercased() ?? ""

        // CRITICAL: Exclude .gifv files (these are videos, not GIFs)
        if urlString.contains(".gifv") || url.pathExtension.lowercased() == "gifv" {
            return false
        }

        // Check if URL has .gif extension (most reliable check)
        if urlString.hasSuffix(".gif") || urlString.contains(".gif?") || urlString.contains(".gif#")
        {
            return true
        }

        // Check file extension from path
        let pathExtension = url.pathExtension.lowercased()
        if pathExtension == "gif" {
            return true
        }

        // Check known GIF hosting domains
        let gifDomains = [
            "media.tenor.com",
            "media.giphy.com",
            "i.giphy.com",
            "media1.giphy.com",
            "media2.giphy.com",
            "media3.giphy.com",
            "media4.giphy.com",
            "c.tenor.com",
            "media1.tenor.com",
        ]

        for domain in gifDomains {
            if host == domain || host.contains(domain) {
                return true
            }
        }

        // Check URL path for gif-like patterns (but be careful not to match "gifv")
        let path = url.path.lowercased()
        if (path.contains("/gif") || path.contains("giphy") || path.contains("tenor"))
            && !path.contains("gifv")
        {
            return true
        }

        return false
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
