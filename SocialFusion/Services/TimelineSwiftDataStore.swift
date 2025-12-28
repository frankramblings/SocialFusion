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
    func saveTimeline(_ posts: [Post]) {
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
                authorAvatarURL: post.authorAvatarURL,
                createdAt: post.createdAt,
                platform: post.platform,
                replyCount: post.replyCount,
                repostCount: post.repostCount,
                likeCount: post.likeCount,
                attachmentURLs: post.attachments.map { $0.url.absoluteString }
            )
            context.insert(cached)
        }
        
        try? context.save()
    }
    
    @MainActor
    func loadTimeline() -> [Post]? {
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
                    authorAvatarURL: cached.authorAvatarURL,
                    createdAt: cached.createdAt,
                    platform: SocialPlatform(rawValue: cached.platformValue) ?? .mastodon,
                    attachments: cached.attachmentURLs.compactMap { urlString in
                        guard let url = URL(string: urlString) else { return nil }
                        return PostAttachment(id: UUID().uuidString, type: .image, url: url, previewURL: url)
                    },
                    replyCount: cached.replyCount,
                    repostCount: cached.repostCount,
                    likeCount: cached.likeCount
                )
            }
        } catch {
            print("Failed to fetch cached posts: \(error)")
            return nil
        }
    }
    
    @MainActor
    func clearAll() {
        try? container.mainContext.delete(model: CachedPost.self)
    }
}

