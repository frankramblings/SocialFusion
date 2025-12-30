import Foundation

final class PostNormalizerImpl: PostNormalizer {
    static let shared = PostNormalizerImpl()

    // Service references - will be set when service manager is available
    private weak var serviceManager: SocialServiceManager?

    private init() {}

    /// Set the service manager for accessing platform services
    func setServiceManager(_ manager: SocialServiceManager) {
        self.serviceManager = manager
    }

    func normalize(_ post: Any) throws -> Post {
        // Type checking and delegation to service conversion methods

        guard let manager = serviceManager else {
            throw PostNormalizationError.missingServiceManager
        }

        // Check for Bluesky post JSON dictionary
        if let blueskyPostJSON = post as? [String: Any] {
            // Check if it's a Bluesky post by looking for Bluesky-specific keys
            if blueskyPostJSON["uri"] != nil || blueskyPostJSON["post"] != nil {
                // This is a Bluesky post JSON dictionary
                // Create a minimal account - the conversion method needs it but may not use all fields
                // We'll use a placeholder that should work for most conversion operations
                let tempAccount = SocialAccount(
                    id: UUID().uuidString,
                    username: "temp",
                    displayName: "Temp",
                    serverURL: URL(string: "https://bsky.social"),
                    platform: .bluesky
                )
                tempAccount.platformSpecificId = ""

                // Use BlueskyService's conversion method
                if let normalizedPost = manager.blueskyService.convertBlueskyPostJSONToPost(
                    blueskyPostJSON, account: tempAccount)
                {
                    return normalizedPost
                }
                throw PostNormalizationError.invalidPostData
            }
        }

        // Check for MastodonStatus
        if let mastodonStatus = post as? MastodonStatus {
            // Mastodon conversion accepts nil account, but we'll pass a minimal one for consistency
            let tempAccount = SocialAccount(
                id: UUID().uuidString,
                username: "temp",
                displayName: "Temp",
                serverURL: URL(string: "https://mastodon.social"),
                platform: .mastodon
            )
            tempAccount.platformSpecificId = ""

            return manager.mastodonService.convertMastodonStatusToPost(
                mastodonStatus, account: tempAccount)
        }

        // Check for BlueskyPost struct
        if let blueskyPost = post as? BlueskyPost {
            return manager.blueskyService.convertBlueskyPostToOriginalPost(blueskyPost)
        }

        throw PostNormalizationError.unsupportedPostType
    }

    func normalizeContent(_ content: String) -> String {
        var normalized = content

        // HTML entity decoding
        normalized =
            normalized
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#8217;", with: "'")
            .replacingOccurrences(of: "&#8216;", with: "'")
            .replacingOccurrences(of: "&#8220;", with: "\"")
            .replacingOccurrences(of: "&#8221;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")

        // Strip HTML tags (basic implementation)
        normalized = normalized.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Normalize whitespace
        normalized =
            normalized
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized
    }
}

enum PostNormalizationError: Error, LocalizedError {
    case unsupportedPostType
    case invalidPostData
    case missingServiceManager
    case noAccountAvailable(platform: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedPostType:
            return "Unsupported post type"
        case .invalidPostData:
            return "Invalid post data"
        case .missingServiceManager:
            return "Service manager not available"
        case .noAccountAvailable(let platform):
            return "No \(platform) account available"
        }
    }
}
