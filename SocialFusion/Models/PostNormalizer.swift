import Foundation

/// Protocol for normalizing posts from different social platforms into a unified format
public protocol PostNormalizer {
    /// Normalizes a post from a specific platform into a unified Post format
    /// - Parameter post: The platform-specific post data
    /// - Returns: A normalized Post object
    func normalize(_ post: Any) throws -> Post
}
