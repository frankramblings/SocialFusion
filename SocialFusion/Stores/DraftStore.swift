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
    
    public func saveDraft(
        posts: [ThreadPost], 
        platforms: Set<SocialPlatform>, 
        replyingToId: String? = nil,
        selectedAccounts: [SocialPlatform: String] = [:]
    ) {
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
        var draft = DraftPost(
            posts: draftPosts,
            selectedPlatforms: platforms,
            replyingToId: replyingToId,
            cwEnabled: firstPost.cwEnabled,
            cwText: firstPost.cwText
        )
        draft.selectedAccounts = selectedAccounts
        drafts.insert(draft, at: 0)
        sortDrafts()
        persist()
    }
    
    public func renameDraft(_ draft: DraftPost, newName: String) {
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index].name = newName.isEmpty ? nil : newName
            persist()
        }
    }
    
    public func togglePin(_ draft: DraftPost) {
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index].isPinned.toggle()
            sortDrafts()
            persist()
        }
    }
    
    private func sortDrafts() {
        drafts.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return lhs.createdAt > rhs.createdAt
        }
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
            sortDrafts()
        } catch {
            print("Failed to load drafts: \(error)")
        }
    }
}

