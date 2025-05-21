import Foundation

// Extracts links from a given string
func extractLinks(from text: String) -> [URL]? {
    var processedText = text
    let hashtagRegex = try? NSRegularExpression(pattern: "#\\w+", options: [])
    if let regex = hashtagRegex {
        processedText = regex.stringByReplacingMatches(
            in: processedText,
            options: [],
            range: NSRange(location: 0, length: processedText.utf16.count),
            withTemplate: ""
        )
    }
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    let matches = detector?.matches(
        in: processedText,
        options: [],
        range: NSRange(location: 0, length: processedText.utf16.count)
    )
    let filteredURLs = matches?.compactMap { match -> URL? in
        guard let url = match.url else { return nil }
        let validatedURL = validateURL(url)
        // Exclude hashtags, mentions, and custom mention/tag schemes
        if isLikelyHashtagOrMention(validatedURL) || validatedURL.scheme == "socialfusion" {
            return nil
        }
        if let host = validatedURL.host?.lowercased() {
            if host.contains("#") || host.contains("workingclass") || host.contains("laborhistory")
                || host.contains("actuallyautistic") || host.contains("dictatorship")
                || host.contains("humanrights") || host.contains("uprising")
            {
                return nil
            }
        }
        return validatedURL
    }
    return filteredURLs
}

// More thorough check for hashtags and mentions
func isLikelyHashtagOrMention(_ url: URL) -> Bool {
    if url.scheme == "socialfusion" {
        return url.host == "tag" || url.host == "user"
    }
    let urlString = url.absoluteString.lowercased()
    if urlString.contains("#") || urlString.hasPrefix("@") {
        return true
    }
    if url.host?.contains(".social") == true || url.host?.contains("mastodon") == true {
        if urlString.contains("tag/") || urlString.contains("tags/")
            || urlString.contains("hashtag/")
        {
            return true
        }
    }
    let pathComponents = url.pathComponents
    for component in pathComponents {
        let lower = component.lowercased()
        if lower.hasPrefix("#") || lower == "tag" || lower == "tags" || lower == "trending"
            || lower == "hashtag"
        {
            return true
        }
    }
    return false
}

// Basic URL validation
func validateURL(_ url: URL) -> URL {
    var fixedURL = url
    if url.scheme == nil {
        if let urlWithScheme = URL(string: "https://" + url.absoluteString) {
            fixedURL = urlWithScheme
        }
    }
    return fixedURL
}

// Local URL service wrapper for link detection
class URLServiceWrapper {
    static let shared = URLServiceWrapper()
    private init() {}
    func isBlueskyPostURL(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        let isBlueskyDomain = host.contains("bsky.app") || host.contains("bsky.social")
        let path = url.path
        let isPostURL = path.contains("/profile/") && path.contains("/post/")
        return isBlueskyDomain && isPostURL
    }
    func isMastodonPostURL(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        let isMastodonInstance =
            host.contains("mastodon.social") || host.contains("mastodon.online")
            || host.contains("mas.to") || host.contains("mastodon.world")
            || host.contains(".social")
        let path = url.path
        let isPostURL = path.contains("/@") && path.split(separator: "/").count >= 3
        return isMastodonInstance && isPostURL
    }
}
