import SwiftUI

/// Environment object to handle post navigation throughout the app
class PostNavigationEnvironment: ObservableObject {
    @Published var selectedPost: Post? = nil

    func navigateToPost(_ post: Post) {
        print("🧭 [PostNavigationEnvironment] Navigating to post: \(post.id) by \(post.authorName)")
        selectedPost = post
    }
}
