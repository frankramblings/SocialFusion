import Combine
import Foundation
import SwiftUI

/// Abstraction over thread loading used by `FusedConversationViewModel`.
///
/// The production adapter (`SocialServiceManagerThreadFetcher`) wraps
/// `SocialServiceManager.fetchThreadContext` and flattens the resulting
/// `ThreadContext` into `(root, descendants)`. Tests substitute a stub.
///
/// Kept colocated with the view model because Task 9 is the only consumer.
/// Tasks 10/11 (view + routing) build on top of this same protocol.
@MainActor
public protocol FusedConversationThreadFetching: AnyObject {
    /// Fetch the thread for a given post: the root post and its replies
    /// (descendants), in any order. The view model sorts them by `createdAt`
    /// at merge time.
    func fetchThread(
        postID: String,
        platform: SocialPlatform
    ) async throws -> (root: Post, replies: [Post])
}

/// The unified merged-thread state for a `FusedMoment`. Loads both sides'
/// reply trees in parallel, merges them by time, streams results as they
/// arrive, and tolerates one-side outages without blocking the working side.
@MainActor
public final class FusedConversationViewModel: ObservableObject {
    public enum SideStatus: Equatable {
        case loading
        case loaded
        case failed(message: String)
    }

    public struct MergedReply: Identifiable, Equatable {
        public let id: String
        public let post: Post

        public var sourcePlatform: SocialPlatform { post.platform }

        public init(id: String, post: Post) {
            self.id = id
            self.post = post
        }

        public static func == (lhs: MergedReply, rhs: MergedReply) -> Bool {
            lhs.id == rhs.id && lhs.post.platform == rhs.post.platform
                && lhs.post.createdAt == rhs.post.createdAt
        }
    }

    @Published public private(set) var moment: FusedMoment
    @Published public private(set) var rootPost: Post?
    /// Per-platform root posts. Each is populated when that side's thread
    /// fetch resolves successfully. The reply dispatch path needs both
    /// (a real `Post` object — Bluesky needs `cid`, Mastodon needs
    /// `originalURL` for cross-instance resolution).
    @Published public private(set) var mastodonRootPost: Post?
    @Published public private(set) var blueskyRootPost: Post?
    @Published public private(set) var replies: [MergedReply] = []
    @Published public private(set) var mastodonStatus: SideStatus = .loading
    @Published public private(set) var blueskyStatus: SideStatus = .loading

    /// True if one side failed and the user has chosen to dismiss its banner.
    @Published public var dismissedFailureBanners: Set<SocialPlatform> = []

    private let threadFetcher: FusedConversationThreadFetching

    public init(
        moment: FusedMoment,
        threadFetcher: FusedConversationThreadFetching
    ) {
        self.moment = moment
        self.threadFetcher = threadFetcher
    }

    /// Kicks off parallel loading of both sides. Streams results into
    /// `replies` as each side resolves so the UI never waits for the slower
    /// network.
    public func load() async {
        async let masto: Void = loadSide(.mastodon)
        async let bsky: Void = loadSide(.bluesky)
        _ = await (masto, bsky)
    }

    /// Retry a single side after a failure. Flips status back to `.loading`
    /// before re-fetching so the UI can reflect the in-flight state.
    public func retry(_ platform: SocialPlatform) async {
        setStatus(.loading, for: platform)
        await loadSide(platform)
    }

    /// Insert a freshly-sent reply into the merged stream without waiting for
    /// the next thread fetch. Idempotent: if a reply with the same id is
    /// already present (e.g., a parallel server poll raced us), nothing
    /// changes. Sorts the merged list in place so the new row lands in
    /// chronological order with the rest.
    public func insertSentReply(_ post: Post) {
        let id = post.id
        guard !replies.contains(where: { $0.id == id }) else { return }
        var combined = replies + [MergedReply(id: id, post: post)]
        combined.sort { $0.post.createdAt < $1.post.createdAt }
        replies = combined
    }

    private func loadSide(_ platform: SocialPlatform) async {
        let postID =
            (platform == .mastodon) ? moment.mastodonPostID : moment.blueskyPostID
        do {
            let result = try await threadFetcher.fetchThread(
                postID: postID, platform: platform)
            if rootPost == nil { rootPost = result.root }
            switch platform {
            case .mastodon: mastodonRootPost = result.root
            case .bluesky: blueskyRootPost = result.root
            }
            mergeAndPublish(result.replies)
            setStatus(.loaded, for: platform)
        } catch {
            setStatus(.failed(message: error.localizedDescription), for: platform)
        }
    }

    private func mergeAndPublish(_ newReplies: [Post]) {
        var combined =
            replies + newReplies.map { MergedReply(id: $0.id, post: $0) }
        // De-dup by id (defensive: same reply should not appear via both sides,
        // but the API could echo and we never want duplicates rendered).
        var seen = Set<String>()
        combined = combined.filter { seen.insert($0.id).inserted }
        // Sort by createdAt ascending — oldest reply first, matching how
        // single-platform thread views read top-down.
        combined.sort { $0.post.createdAt < $1.post.createdAt }
        replies = combined
    }

    private func setStatus(_ status: SideStatus, for platform: SocialPlatform) {
        switch platform {
        case .mastodon: mastodonStatus = status
        case .bluesky: blueskyStatus = status
        }
    }
}

// MARK: - Production adapter

/// Adapter that wraps `SocialServiceManager.fetchThreadContext` so the view
/// model can be driven by the real services in production. Constructed at the
/// route boundary (Task 11) where a `SocialServiceManager` is in scope.
@MainActor
public final class SocialServiceManagerThreadFetcher: FusedConversationThreadFetching {
    private let serviceManager: SocialServiceManager

    public init(serviceManager: SocialServiceManager) {
        self.serviceManager = serviceManager
    }

    public func fetchThread(
        postID: String,
        platform: SocialPlatform
    ) async throws -> (root: Post, replies: [Post]) {
        // `fetchThreadContext(for:)` only reads `post.platform` and
        // `post.platformSpecificId` from the probe, so a minimal stub is safe.
        let probe = Post(
            id: postID,
            content: "",
            authorName: "",
            authorUsername: "",
            authorId: "",
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: platform,
            originalURL: "",
            attachments: [],
            mentions: [],
            tags: [],
            platformSpecificId: postID
        )
        let context = try await serviceManager.fetchThreadContext(for: probe)
        let root = context.mainPost ?? probe
        return (root: root, replies: context.descendants)
    }
}
