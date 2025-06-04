import Foundation
import SocialFusion.Models

final class PostNormalizerImpl: PostNormalizer {
    static let shared = PostNormalizerImpl()
    private init() {}

    func normalizeContent(_ content: String) -> String {
        // Add normalization logic here (previously in PostNormalizer.swift)
        // For now, just return the content as-is
        return content
    }
}

// Platform-specific models (if needed)
// struct BlueskyPost { ... }
// struct MastodonPost { ... }
