import Foundation
import SwiftUI

/// Model for managing the link that should be previewed when a post contains multiple links
class PreviewLinkSelection: ObservableObject {
    static let shared = PreviewLinkSelection()

    /// Dictionary to store which links should be previewed for each post
    @Published private var selectedLinksForPosts: [String: URL] = [:]

    /// Dictionary to track if link preview is disabled for specific posts
    @Published private var disabledPreviewsForPosts: Set<String> = []

    private init() {}

    /// Set the selected link to preview for a post
    /// - Parameters:
    ///   - url: The URL to preview
    ///   - postId: The ID of the post
    func setSelectedLink(url: URL, for postId: String) {
        selectedLinksForPosts[postId] = url
        // Enable previews when a specific link is selected
        disabledPreviewsForPosts.remove(postId)
    }

    /// Get the selected link for preview for a post
    /// - Parameter postId: The ID of the post
    /// - Returns: The selected URL, or nil if none is selected
    func getSelectedLink(for postId: String) -> URL? {
        return selectedLinksForPosts[postId]
    }

    /// Disable link previews for a specific post
    /// - Parameter postId: The ID of the post
    func disablePreviews(for postId: String) {
        disabledPreviewsForPosts.insert(postId)
        // Remove any selected link
        selectedLinksForPosts.removeValue(forKey: postId)
    }

    /// Enable link previews for a specific post
    /// - Parameter postId: The ID of the post
    func enablePreviews(for postId: String) {
        disabledPreviewsForPosts.remove(postId)
    }

    /// Check if previews are disabled for a specific post
    /// - Parameter postId: The ID of the post
    /// - Returns: True if previews are disabled
    func arePreviewsDisabled(for postId: String) -> Bool {
        return disabledPreviewsForPosts.contains(postId)
    }

    /// Clear all selections for a post
    /// - Parameter postId: The ID of the post
    func clearSelections(for postId: String) {
        selectedLinksForPosts.removeValue(forKey: postId)
        disabledPreviewsForPosts.remove(postId)
    }
}
