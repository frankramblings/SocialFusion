import Foundation

/// Legacy link detection functions that delegate to URLService
/// This file is maintained for backward compatibility

// Extracts links from a given string
func extractLinks(from text: String) -> [URL]? {
    let links = URLService.shared.extractLinks(from: text)
    return links.isEmpty ? nil : links
}

// Check for hashtags and mentions using URLService
func isLikelyHashtagOrMention(_ url: URL) -> Bool {
    return URLService.shared.isHashtagOrMentionURL(url)
}

// Basic URL validation using URLService
func validateURL(_ url: URL) -> URL {
    return URLService.shared.validateURL(url)
}

// Simplified URL service wrapper for link detection
class URLServiceWrapper {
    static let shared = URLServiceWrapper()
    private init() {}

    func isBlueskyPostURL(_ url: URL) -> Bool {
        return URLService.shared.isBlueskyPostURL(url)
    }

    func isMastodonPostURL(_ url: URL) -> Bool {
        return URLService.shared.isMastodonPostURL(url)
    }
}
