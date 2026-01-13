import Foundation
import Combine

@MainActor
public class DraftStore: ObservableObject {
    @Published public var drafts: [DraftPost] = []
    
    private let fileManager = FileManager.default
    private var draftsURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("drafts.json")
    }
    
    public init() {
        loadDrafts()
    }
    
    public func saveDraft(posts: [ThreadPost], platforms: Set<SocialPlatform>, replyingToId: String? = nil) {
        let draftPosts = posts.map { post in
            ThreadPostDraft(
                text: post.text,
                mediaData: post.images.compactMap { $0.jpegData(compressionQuality: 0.8) },
                cwEnabled: post.cwEnabled,
                cwText: post.cwText,
                attachmentAltTexts: post.imageAltTexts,
                attachmentSensitiveFlags: post.attachmentSensitiveFlags
            )
        }
        
        // Use first post's CW for legacy support
        let firstPost = posts.first ?? ThreadPost()
        let draft = DraftPost(
            posts: draftPosts,
            selectedPlatforms: platforms,
            replyingToId: replyingToId,
            cwEnabled: firstPost.cwEnabled,
            cwText: firstPost.cwText
        )
        drafts.insert(draft, at: 0)
        persist()
    }
    
    public func deleteDraft(_ draft: DraftPost) {
        drafts.removeAll { $0.id == draft.id }
        persist()
    }
    
    public func clearAllDrafts() {
        drafts.removeAll()
        persist()
    }
    
    private func persist() {
        Task.detached(priority: .background) {
            do {
                let data = try JSONEncoder().encode(await self.drafts)
                try data.write(to: await self.draftsURL, options: [.atomic, .completeFileProtection])
            } catch {
                print("Failed to persist drafts: \(error)")
            }
        }
    }
    
    private func loadDrafts() {
        guard fileManager.fileExists(atPath: draftsURL.path) else { return }
        do {
            let data = try Data(contentsOf: draftsURL)
            drafts = try JSONDecoder().decode([DraftPost].self, from: data)
        } catch {
            print("Failed to load drafts: \(error)")
        }
    }
}

