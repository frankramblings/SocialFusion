import Foundation
import SwiftData
import SwiftUI

@available(iOS 17.0, *)
actor TimelineSwiftDataStore {
    static let shared = TimelineSwiftDataStore()
    
    private let container: ModelContainer
    
    private init() {
        do {
            container = try ModelContainer(for: CachedPost.self)
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }
    }
    
    @MainActor
    func saveTimeline(_ posts: [Post]) async {
        let context = container.mainContext
        
        // Clear old cache
        try? context.delete(model: CachedPost.self)
        
        // Add new posts
        for post in posts.prefix(100) { // Cache top 100 posts for offline reading
            let cached = CachedPost(
                id: post.id,
                content: post.content,
                authorName: post.authorName,
                authorUsername: post.authorUsername,
                authorProfilePictureURL: post.authorProfilePictureURL,
                createdAt: post.createdAt,
                platform: post.platform,
                originalURL: post.originalURL,
                replyCount: post.replyCount,
                repostCount: post.repostCount,
                likeCount: post.likeCount,
                attachmentURLs: post.attachments.map { $0.url }
            )
            context.insert(cached)
        }
        
        try? context.save()
    }
    
    @MainActor
    func loadTimeline() async -> [Post]? {
        let context = container.mainContext
        let descriptor = FetchDescriptor<CachedPost>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        
        do {
            let cachedPosts = try context.fetch(descriptor)
            return cachedPosts.map { cached in
                Post(
                    id: cached.id,
                    content: cached.content,
                    authorName: cached.authorName,
                    authorUsername: cached.authorUsername,
                    authorProfilePictureURL: cached.authorProfilePictureURL,
                    createdAt: cached.createdAt,
                    platform: SocialPlatform(rawValue: cached.platformValue) ?? .mastodon,
                    originalURL: cached.originalURL,
                    attachments: cached.attachmentURLs.map { urlString in
                        Post.Attachment(url: urlString, type: .image)
                    },
                    likeCount: cached.likeCount,
                    repostCount: cached.repostCount,
                    replyCount: cached.replyCount
                )
            }
        } catch {
            print("Failed to fetch cached posts: \(error)")
            return nil
        }
    }
    
    @MainActor
    func clearAll() async {
        try? container.mainContext.delete(model: CachedPost.self)
    }
}

