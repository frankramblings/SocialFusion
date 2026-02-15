import Foundation
import SwiftData
import os.log

@available(iOS 17.0, *)
actor TimelineSwiftDataStore {
    static let shared = TimelineSwiftDataStore()
    
    private let container: ModelContainer
    private let logger = Logger(subsystem: "com.socialfusion", category: "TimelineSwiftDataStore")
    
    private init() {
        do {
            let fileManager = FileManager.default
            guard let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw CocoaError(.fileNoSuchFile)
            }

            // Ensure Application Support exists before SwiftData tries to create the store file.
            try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
            let storeURL = appSupportDirectory.appendingPathComponent("default.store")
            let configuration = ModelConfiguration(url: storeURL)

            container = try ModelContainer(for: CachedPost.self, configurations: configuration)
        } catch {
            assertionFailure("Failed to initialize SwiftData container, falling back to in-memory store: \(error)")
            do {
                let memoryOnlyConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                container = try ModelContainer(for: CachedPost.self, configurations: memoryOnlyConfig)
            } catch {
                fatalError("Failed to initialize SwiftData container (even in-memory): \(error)")
            }
        }
    }
    
    func saveTimeline(_ posts: [Post]) async {
        let context = ModelContext(container)

        do {
            try context.delete(model: CachedPost.self)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            for post in posts.prefix(100) { // Cache top 100 posts for offline reading
                let postData = try? encoder.encode(post)

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
                    attachmentURLs: post.attachments.map { $0.url },
                    postData: postData
                )
                context.insert(cached)
            }

            try context.save()
        } catch {
            logger.error("save_timeline_failed error=\(error.localizedDescription, privacy: .public)")
        }
    }
    
    func loadTimeline() async -> [Post]? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<CachedPost>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        
        do {
            let cachedPosts = try context.fetch(descriptor)
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            return cachedPosts.compactMap { cached in
                // Try to decode full post data first
                if let postData = cached.postData,
                   let decodedPost = try? decoder.decode(Post.self, from: postData) {
                    return decodedPost
                }
                
                // Fallback to manual reconstruction for older cache entries
                return Post(
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
            logger.error("load_timeline_failed error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    func clearAll() async {
        let context = ModelContext(container)
        do {
            try context.delete(model: CachedPost.self)
            try context.save()
        } catch {
            logger.error("clear_timeline_failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    /// Returns the combined file size of the SwiftData store files (default.store, -wal, -shm)
    func getStoreSize() -> Int64 {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return 0
        }

        let storeFiles = ["default.store", "default.store-wal", "default.store-shm"]
        var totalSize: Int64 = 0

        for file in storeFiles {
            let url = appSupport.appendingPathComponent(file)
            if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                totalSize += size
            }
        }

        return totalSize
    }
}
