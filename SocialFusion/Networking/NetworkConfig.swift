import Foundation
import UIKit

/// Global network configuration settings
struct NetworkConfig {
    // Default timeout values
    static let defaultRequestTimeout: TimeInterval = 15.0
    static let shortTimeout: TimeInterval = 5.0
    static let longTimeout: TimeInterval = 30.0

    // Concurrency limits
    static let maxConcurrentConnections = 4
    static let maxConcurrentDownloads = 2

    // Retry configuration
    static let maxRetryAttempts = 2
    static let retryDelay: TimeInterval = 2.0
    static let exponentialBackoffMultiplier = 1.5

    // Cache configuration
    static let defaultCachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    static let cacheTTL: TimeInterval = 300  // 5 minutes

    // User agent string
    static let userAgent = "SocialFusion/1.0 iOS/\(UIDevice.current.systemVersion) (iPhone)"

    // Common headers dictionary
    static var commonHeaders: [String: String] {
        return [
            "User-Agent": userAgent,
            "Accept": "application/json",
            "Accept-Language": Locale.current.language.languageCode?.identifier ?? "en",
        ]
    }

    // Social media API hosts for domain filtering
    static let socialMediaHosts = [
        "api.bsky.app",
        "bsky.social",
        "mastodon.social",
        "mastodon.online",
        "mas.to",
    ]

    // Blocked domains that cause issues
    static let blockedDomains = [
        "www.threads.net",
        "threads.net",
    ]

    // Check if a domain is in the blocked list
    static func isBlockedDomain(_ domain: String) -> Bool {
        return blockedDomains.contains {
            domain.lowercased().contains($0.lowercased())
        }
    }

    // Check if request should be allowed to proceed
    static func shouldAllowRequest(for url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }

        // Block known problematic domains
        if isBlockedDomain(host) {
            return false
        }

        // Must have http or https scheme
        guard let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return false
        }

        return true
    }
}
