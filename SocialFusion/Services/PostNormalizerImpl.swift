import Foundation

final class PostNormalizerImpl: PostNormalizer {
    static let shared = PostNormalizerImpl()
    private init() {}

    func normalize(_ post: Any) throws -> Post {
        // TODO: Implement platform-specific normalization logic
        // For now, throw an error to indicate this needs implementation
        throw PostNormalizationError.unsupportedPostType
    }

    func normalizeContent(_ content: String) -> String {
        // Add normalization logic here (previously in PostNormalizer.swift)
        // For now, just return the content as-is
        return content
    }
}

enum PostNormalizationError: Error {
    case unsupportedPostType
    case invalidPostData
}

// Platform-specific models (if needed)
// struct BlueskyPost { ... }
// struct MastodonPost { ... }
