import Combine
import Foundation

struct SocialFusionError: Identifiable {
    let id = UUID()
    let message: String
}

@MainActor
final class PostStore: ObservableObject {
    static let shared = PostStore()
    @Published private(set) var posts: [String: Post] = [:]
    @Published var error: SocialFusionError?

    // Insert or update a post
    func upsert(_ post: Post) {
        posts[post.stableId] = post
    }

    // Insert or update multiple posts
    func upsert(_ newPosts: [Post]) {
        for post in newPosts { upsert(post) }
    }

    // Get a post by its stable ID
    func getPost(byStableId stableId: String) -> Post? {
        return posts[stableId]
    }

    // Optimistic like
    func like(postID: String, service: SocialServiceManager, account: SocialAccount) async {
        guard var post = posts[postID] else { return }
        let prevLiked = post.isLiked
        let prevCount = post.likeCount
        // Optimistic update
        post.isLiked = true
        post.likeCount += 1
        upsert(post)
        do {
            let updated = try await service.likePost(post)
            upsert(updated)
        } catch {
            // Rollback
            post.isLiked = prevLiked
            post.likeCount = prevCount
            upsert(post)
            self.error = SocialFusionError(
                message: "Failed to like post: \(error.localizedDescription)")
        }
    }

    // Optimistic repost (stub for future)
    func repost(postID: String, service: SocialServiceManager, account: SocialAccount) async {
        guard var post = posts[postID] else { return }
        let prevReposted = post.isReposted
        let prevCount = post.repostCount
        post.isReposted = true
        post.repostCount += 1
        upsert(post)
        do {
            let updated = try await service.repostPost(post)
            upsert(updated)
        } catch {
            post.isReposted = prevReposted
            post.repostCount = prevCount
            upsert(post)
            self.error = SocialFusionError(
                message: "Failed to repost: \(error.localizedDescription)")
        }
    }
}
