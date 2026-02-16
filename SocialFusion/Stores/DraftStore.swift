import Foundation
import Combine
import UIKit
import os.log

@MainActor
public class DraftStore: ObservableObject {
    @Published public var drafts: [DraftPost] = []
    
    private let fileManager = FileManager.default
    private let persistenceQueue = DraftPersistenceQueue()
    private let logger = Logger(subsystem: "com.socialfusion", category: "DraftStore")
    private var draftsURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("drafts.json")
    }
    
    public init() {
        loadDraftsAsync()
    }
    
    public func saveDraft(
        posts: [ThreadPost], 
        platforms: Set<SocialPlatform>, 
        replyingToId: String? = nil,
        selectedAccounts: [SocialPlatform: String] = [:]
    ) {
        let snapshots = posts.map(ThreadPostSnapshot.init(post:))
        let firstPost = posts.first ?? ThreadPost()

        Task {
            let draftPosts = await persistenceQueue.encodeDraftPosts(from: snapshots)
            await MainActor.run {
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
        }
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
        let snapshot = drafts
        let destinationURL = draftsURL
        Task {
            await persistenceQueue.enqueuePersist(drafts: snapshot, destinationURL: destinationURL)
        }
    }
    
    /// Load drafts asynchronously to avoid blocking the main thread with file I/O and decode.
    private func loadDraftsAsync() {
        let url = draftsURL
        Task.detached(priority: .userInitiated) { [weak self] in
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode([DraftPost].self, from: data)
                await self?.applyLoadedDrafts(decoded)
            } catch {
                await MainActor.run {
                    self?.logger.error("load_drafts_failed error=\(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func applyLoadedDrafts(_ loaded: [DraftPost]) {
        drafts = loaded
        sortDrafts()
    }
}

final class DraftImageBox: @unchecked Sendable {
    let image: UIImage

    init(image: UIImage) {
        self.image = image
    }
}

struct ThreadPostSnapshot: Sendable {
    let text: String
    let images: [DraftImageBox]
    let cwEnabled: Bool
    let cwText: String
    let attachmentAltTexts: [String]
    let attachmentSensitiveFlags: [Bool]

    init(post: ThreadPost) {
        self.text = post.text
        self.images = post.images.map { DraftImageBox(image: $0) }
        self.cwEnabled = post.cwEnabled
        self.cwText = post.cwText
        self.attachmentAltTexts = post.imageAltTexts
        self.attachmentSensitiveFlags = post.attachmentSensitiveFlags
    }
}
