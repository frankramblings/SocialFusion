import SwiftUI

/// Environment object to handle post navigation throughout the app
class PostNavigationEnvironment: ObservableObject {
    @Published var selectedPost: Post? = nil
    @Published var boostInfo: (boostedBy: String, boostedAt: Date)? = nil

    func navigateToPost(_ post: Post) {
        print("🧭 [PostNavigationEnvironment] Navigating to post: \(post.id) by \(post.authorName)")

        // If this is a boost post, navigate to the original post but preserve boost info
        if let originalPost = post.originalPost, let boostedBy = post.boostedBy {
            print(
                "🧭 [PostNavigationEnvironment] Boost detected - navigating to original post: \(originalPost.id)"
            )
            selectedPost = originalPost
            boostInfo = (boostedBy: boostedBy, boostedAt: post.createdAt)
        } else {
            selectedPost = post
            boostInfo = nil
        }
    }

    /// Clear navigation state
    func clearNavigation() {
        selectedPost = nil
        boostInfo = nil
    }
}
