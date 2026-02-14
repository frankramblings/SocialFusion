import Foundation
import SwiftData
import SwiftUI

/// Service for tracking read state of posts
/// Uses SwiftData on iOS 17+ with UserDefaults fallback for iOS 16
@MainActor
class ViewTracker {
    static let shared = ViewTracker()

    // In-memory cache for fast synchronous lookups
    private var readPostIds: Set<String> = []
    private var lastReadPostId: String?
    private var lastReadDate: Date?

    // Persistence
    private var persistenceTask: Task<Void, Never>?
    private var pendingSave = false
    private var pendingReadEntriesByPostId: [String: String] = [:]
    private let persistDebounceNanoseconds: UInt64 = 500_000_000

    // UserDefaults keys (for iOS 16 fallback)
    private let readPostsKey = "read_posts"
    private let lastReadPostIdKey = "last_read_post_id"
    private let lastReadDateKey = "last_read_date"

    // SwiftData container (iOS 17+) - use type-erased storage to avoid @available on stored property
    private var _containerStorage: Any?

    @available(iOS 17.0, *)
    private var container: ModelContainer? {
        get {
            if _containerStorage == nil {
                initializeSwiftDataContainer()
            }
            return _containerStorage as? ModelContainer
        }
        set {
            _containerStorage = newValue
        }
    }

    private init() {
        loadPersistedState()
    }

    // MARK: - Public API

    /// Check if a post has been read (synchronous, uses in-memory cache)
    func isRead(postId: String) -> Bool {
        return readPostIds.contains(postId)
    }

    /// Mark a post as read (async, non-blocking)
    func markAsRead(postId: String, stableId: String) async {
        // Update in-memory cache immediately (synchronous)
        guard !readPostIds.contains(postId) else { return }

        readPostIds.insert(postId)
        lastReadPostId = postId
        lastReadDate = Date()
        pendingReadEntriesByPostId[postId] = stableId
        pendingSave = true

        schedulePersistenceFlush()
    }

    /// Get the most recent read post ID
    func getLastReadPostId() -> String? {
        return lastReadPostId
    }

    /// Get the date of the most recent read
    func getLastReadDate() -> Date? {
        return lastReadDate
    }

    /// Clear all read state
    func clearReadState() {
        persistenceTask?.cancel()
        persistenceTask = nil
        pendingSave = false
        pendingReadEntriesByPostId.removeAll()

        readPostIds.removeAll()
        lastReadPostId = nil
        lastReadDate = nil

        if #available(iOS 17.0, *) {
            Task {
                await clearSwiftData()
            }
        } else {
            UserDefaults.standard.removeObject(forKey: readPostsKey)
            UserDefaults.standard.removeObject(forKey: lastReadPostIdKey)
            UserDefaults.standard.removeObject(forKey: lastReadDateKey)
        }
    }

    // MARK: - iOS 17+ SwiftData Implementation

    @available(iOS 17.0, *)
    private func initializeSwiftDataContainer() {
        do {
            let fileManager = FileManager.default
            guard
                let appSupportDirectory = fileManager.urls(
                    for: .applicationSupportDirectory, in: .userDomainMask
                ).first
            else {
                throw CocoaError(.fileNoSuchFile)
            }

            try fileManager.createDirectory(
                at: appSupportDirectory, withIntermediateDirectories: true)
            let storeURL = appSupportDirectory.appendingPathComponent("read_state.store")
            let configuration = ModelConfiguration(schema: Schema([ReadPost.self]), url: storeURL)

            _containerStorage = try ModelContainer(
                for: ReadPost.self, configurations: configuration)
        } catch {
            print("⚠️ ViewTracker: Failed to initialize SwiftData container: \(error)")
            // Fallback to in-memory store
            do {
                let memoryOnlyConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                _containerStorage = try ModelContainer(
                    for: ReadPost.self, configurations: memoryOnlyConfig)
            } catch {
                print(
                    "❌ ViewTracker: Failed to initialize SwiftData container (even in-memory): \(error)"
                )
            }
        }
    }

    @available(iOS 17.0, *)
    private func persistBatchToSwiftData(entries: [(postId: String, stableId: String)]) async {
        guard !entries.isEmpty else { return }
        guard let container = container else { return }

        let context = container.mainContext

        do {
            for entry in entries {
                let entryPostId = entry.postId
                let descriptor = FetchDescriptor<ReadPost>(
                    predicate: #Predicate<ReadPost> { $0.postId == entryPostId }
                )
                let existing = try context.fetch(descriptor)
                if let existingPost = existing.first {
                    existingPost.readAt = Date()
                    existingPost.stableId = entry.stableId
                } else {
                    let readPost = ReadPost(
                        postId: entry.postId,
                        readAt: Date(),
                        stableId: entry.stableId
                    )
                    context.insert(readPost)
                }
            }
            try context.save()
        } catch {
            print("⚠️ ViewTracker: Failed to persist read-state batch: \(error)")
        }
    }

    @available(iOS 17.0, *)
    private func loadFromSwiftData() {
        guard let container = container else { return }

        let context = container.mainContext
        let descriptor = FetchDescriptor<ReadPost>(
            sortBy: [SortDescriptor(\.readAt, order: .reverse)]
        )

        do {
            let readPosts = try context.fetch(descriptor)
            readPostIds = Set(readPosts.map { $0.postId })

            if let mostRecent = readPosts.first {
                lastReadPostId = mostRecent.postId
                lastReadDate = mostRecent.readAt
            }
        } catch {
            print("⚠️ ViewTracker: Failed to load read state: \(error)")
        }
    }

    @available(iOS 17.0, *)
    private func clearSwiftData() async {
        guard let container = container else { return }
        try? container.mainContext.delete(model: ReadPost.self)
    }

    // MARK: - iOS 16 UserDefaults Implementation

    private func persistToUserDefaults() {
        UserDefaults.standard.set(Array(readPostIds), forKey: readPostsKey)
        if let lastReadId = lastReadPostId {
            UserDefaults.standard.set(lastReadId, forKey: lastReadPostIdKey)
        }
        if let lastReadDate = lastReadDate {
            UserDefaults.standard.set(lastReadDate, forKey: lastReadDateKey)
        }
    }

    private func schedulePersistenceFlush() {
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: persistDebounceNanoseconds)
            } catch {
                return
            }
            await self.flushPendingReadState()
        }
    }

    private func flushPendingReadState() async {
        guard pendingSave else { return }
        pendingSave = false

        let entries = pendingReadEntriesByPostId.map { (postId: $0.key, stableId: $0.value) }
        pendingReadEntriesByPostId.removeAll()

        if #available(iOS 17.0, *) {
            await persistBatchToSwiftData(entries: entries)
        } else {
            persistToUserDefaults()
        }
    }

    private func loadFromUserDefaults() {
        if let savedReadPosts = UserDefaults.standard.array(forKey: readPostsKey) as? [String] {
            readPostIds = Set(savedReadPosts)
        }
        lastReadPostId = UserDefaults.standard.string(forKey: lastReadPostIdKey)
        lastReadDate = UserDefaults.standard.object(forKey: lastReadDateKey) as? Date
    }

    // MARK: - Load Persisted State

    private func loadPersistedState() {
        if #available(iOS 17.0, *) {
            initializeSwiftDataContainer()
            loadFromSwiftData()
        } else {
            loadFromUserDefaults()
        }
    }
}
