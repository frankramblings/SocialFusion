import SwiftUI
import UIKit

/// Modifier that conditionally applies clipping
private struct ConditionalClippedModifier: ViewModifier {
    let shouldClip: Bool

    func body(content: Content) -> some View {
        if shouldClip {
            content.clipped()
        } else {
            content
        }
    }
}

/// A view that displays a post card with all its components
struct PostCardView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @ObservedObject var post: Post
    let replyCount: Int
    let repostCount: Int
    let likeCount: Int
    let isReplying: Bool
    let isReposted: Bool
    let isLiked: Bool
    let onAuthorTap: () -> Void
    let onReply: () -> Void
    let onRepost: () -> Void
    let onLike: () -> Void
    let onShare: () -> Void
    let onQuote: () -> Void
    let onMediaTap: (Post.Attachment) -> Void
    let onOpenInBrowser: () -> Void
    let onCopyLink: () -> Void
    let onReport: () -> Void
    let onPostTap: () -> Void
    let onParentPostTap: (Post) -> Void
    @ObservedObject var postActionStore: PostActionStore
    let postActionCoordinator: PostActionCoordinator?

    // Optional boost information
    let boostedBy: String?

    // Optional PostViewModel for state updates
    let viewModel: PostViewModel?

    // State for expanding reply banner - properly keyed to prevent view reuse issues
    @State private var isReplyBannerExpanded = false
    @State private var bannerWasTapped = false
    @State private var showListSelection = false

    // Cached values to prevent AttributeGraph cycles from accessing nested @ObservedObject properties
    @State private var cachedDisplayPost: Post?
    @State private var cachedBoostHandle: String?
    @State private var cachedReplyInfo: (username: String, id: String?, platform: SocialPlatform)?
    @State private var cachedAttachments: [Post.Attachment] = []
    @State private var cachedPlatform: SocialPlatform?
    @State private var cachedPoll: Post.Poll?  // Cache poll to avoid accessing displayPost.poll during rendering
    @State private var cachedBoosterEmojiMap: [String: String]?  // Cache booster emoji for boost banner
    @State private var isUpdatingCache = false  // Prevent recursive cache updates

    // Platform color helper - CRITICAL FIX: Use cached platform only (never access post.platform synchronously)
    private var platformColor: Color {
        // cachedPlatform is always initialized in initializer, so this should never be nil
        // But if it is, use a safe default to prevent crashes
        let platform = cachedPlatform ?? .bluesky
        switch platform {
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
        }
    }
    
    // CRITICAL FIX: Cached platform getter - never access post.platform synchronously
    private var displayPlatform: SocialPlatform {
        // cachedPlatform is always initialized in initializer, so this should never be nil
        // But if it is, use a safe default to prevent crashes
        return cachedPlatform ?? .bluesky
    }

    // Determine which post to display: use original for boosts, otherwise self.post
    // CRITICAL FIX: Only use cached value to prevent AttributeGraph cycles
    // Cache is updated in onAppear/onChange which are outside the rendering cycle
    // CRITICAL: Never access post.originalPost here - always use cached value
    private var displayPost: Post {
        // Always use cached value - it's updated in onAppear/onChange
        // Fallback to post only if cache is truly nil (shouldn't happen after onAppear)
        // This fallback is safe because it doesn't access nested @ObservedObject properties
        return cachedDisplayPost ?? post
    }

    // Get attachments to display - prioritize originalPost attachments for boosts
    // CRITICAL FIX: Only use cached value to prevent AttributeGraph cycles
    private var displayAttachments: [Post.Attachment] {
        // Always use cached value - it's updated in onAppear/onChange
        return cachedAttachments
    }

    // CRITICAL FIX: Removed isBoost computed property that accessed post.originalPost synchronously
    // Boost status is determined in updateCachedValues() and stored in cachedBoostHandle

    // Get the reply info - check displayPost (which is originalPost for boosts)
    // CRITICAL FIX: Only use cached value to prevent AttributeGraph cycles
    private var replyInfo: (username: String, id: String?, platform: SocialPlatform)? {
        // Always use cached value - it's updated in onAppear/onChange
        return cachedReplyInfo
    }
    
    // CRITICAL FIX: Update cached values to prevent AttributeGraph cycles
    // This function extracts values once and caches them, avoiding repeated access to nested @ObservedObject properties
    // CRITICAL: This function must be called outside the view rendering cycle (via Task with delay)
    // CRITICAL: All calculations and state updates are wrapped in Task to ensure they happen outside view update cycle
    private func updateCachedValues() {
        // Prevent recursive calls
        guard !isUpdatingCache else { return }
        isUpdatingCache = true
        defer { isUpdatingCache = false }
        
        // CRITICAL: Wrap ALL calculations and state updates in Task with delay to ensure they happen outside view update cycle
        // This prevents "Modifying state during view update" warnings
        Task { @MainActor in
            // CRITICAL: Add delay before accessing post properties to ensure we're outside view update cycle
            try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2 second delay
            
            // CRITICAL: Capture originalPost and boostedBy references once to avoid multiple accesses
            // Accessing post.originalPost and post.boostedBy triggers didSet which calls objectWillChange
            // By capturing them once, we minimize the number of triggers
            let originalPostRef = post.originalPost
            let postBoostedByRef = post.boostedBy
            
            // Cache platform from displayPost to avoid accessing post.platform synchronously
            let newDisplayPost: Post
            let newPlatform: SocialPlatform
            let isBoost = originalPostRef != nil || (boostedBy ?? postBoostedByRef) != nil
            if isBoost, let original = originalPostRef {
                newDisplayPost = original
                newPlatform = original.platform
            } else {
                newDisplayPost = post
                newPlatform = post.platform
            }
            
            // Only update if value changed to prevent unnecessary view updates
            if cachedDisplayPost?.id != newDisplayPost.id {
                cachedDisplayPost = newDisplayPost
            }
            // Update platform if it changed
            if cachedPlatform != newPlatform {
                cachedPlatform = newPlatform
            }
            
            // Update cached boost handle - only update if value changed
            let hasOriginalPost = originalPostRef != nil
            let finalBoostedBy = boostedBy ?? postBoostedByRef
            let boostHandle = finalBoostedBy?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasBoostHandle = boostHandle != nil && !boostHandle!.isEmpty
            
            let newBoostHandle: String?
            if !hasOriginalPost && !hasBoostHandle {
                newBoostHandle = nil
            } else if let handle = boostHandle, !handle.isEmpty {
                newBoostHandle = handle
            } else if let handle = postBoostedByRef, !handle.isEmpty {
                newBoostHandle = handle
            } else if hasOriginalPost {
                if !post.authorUsername.isEmpty {
                    newBoostHandle = post.authorUsername
                } else if post.id.hasPrefix("repost-") {
                    let components = post.id.split(separator: "-", maxSplits: 2)
                    if components.count >= 2 {
                        newBoostHandle = String(components[1])
                    } else {
                        newBoostHandle = "Someone"
                    }
                } else if let original = originalPostRef, !original.authorUsername.isEmpty {
                    newBoostHandle = original.authorUsername
                } else {
                    newBoostHandle = "Someone"
                }
            } else {
                newBoostHandle = nil
            }
            
            // Only update if value changed
            if cachedBoostHandle != newBoostHandle {
                cachedBoostHandle = newBoostHandle
            }
            
            // Update cached reply info - only update if value changed
            let newReplyInfo: (username: String, id: String?, platform: SocialPlatform)?
            if let original = originalPostRef {
                let originalUsername = original.inReplyToUsername
                let originalReplyID = original.inReplyToID
                if let username = originalUsername, !username.isEmpty {
                    newReplyInfo = (username, originalReplyID, original.platform)
                } else if let username = post.inReplyToUsername, !username.isEmpty {
                    newReplyInfo = (username, post.inReplyToID, post.platform)
                } else {
                    let dp = cachedDisplayPost ?? post
                    let displayUsername = dp.inReplyToUsername
                    let displayReplyID = dp.inReplyToID
                    if let username = displayUsername, !username.isEmpty {
                        newReplyInfo = (username, displayReplyID, dp.platform)
                    } else if displayReplyID != nil {
                        newReplyInfo = ("someone", displayReplyID, dp.platform)
                    } else {
                        newReplyInfo = nil
                    }
                }
            } else if let username = post.inReplyToUsername, !username.isEmpty {
                newReplyInfo = (username, post.inReplyToID, post.platform)
            } else {
                let dp = cachedDisplayPost ?? post
                let displayUsername = dp.inReplyToUsername
                let displayReplyID = dp.inReplyToID
                if let username = displayUsername, !username.isEmpty {
                    newReplyInfo = (username, displayReplyID, dp.platform)
                } else if displayReplyID != nil {
                    newReplyInfo = ("someone", displayReplyID, dp.platform)
                } else {
                    newReplyInfo = nil
                }
            }
            
            // Only update if value changed
            if cachedReplyInfo?.username != newReplyInfo?.username ||
               cachedReplyInfo?.id != newReplyInfo?.id ||
               cachedReplyInfo?.platform != newReplyInfo?.platform {
                cachedReplyInfo = newReplyInfo
            }
            
            // Update cached attachments - only update if value changed
            let newAttachments: [Post.Attachment]
            if let original = originalPostRef {
                if !original.attachments.isEmpty {
                    newAttachments = original.attachments
                } else {
                    let dp = cachedDisplayPost ?? post
                    newAttachments = dp.attachments
                }
            } else {
                let dp = cachedDisplayPost ?? post
                newAttachments = dp.attachments
            }
            
            // Only update if attachments changed (compare by count and first URL)
            if cachedAttachments.count != newAttachments.count ||
               (cachedAttachments.first?.url != newAttachments.first?.url) {
                cachedAttachments = newAttachments
            }
            
            // Update cached poll - only update if value changed
            let newPoll: Post.Poll?
            if let original = originalPostRef {
                newPoll = original.poll
            } else {
                let dp = cachedDisplayPost ?? post
                newPoll = dp.poll
            }
            
            // Only update if poll changed (compare by value)
            if cachedPoll != newPoll {
                cachedPoll = newPoll
            }

            // Update cached booster emoji map - only update if value changed
            let newBoosterEmojiMap = post.boosterEmojiMap
            if cachedBoosterEmojiMap != newBoosterEmojiMap {
                cachedBoosterEmojiMap = newBoosterEmojiMap
            }
        }
    }
    
    // CRITICAL FIX: Defer logging to prevent AttributeGraph cycles from accessing post.originalPost
    private func logBannerState() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)  // Longer delay to ensure outside view update cycle
            // CRITICAL: Capture references once to avoid multiple synchronous accesses
            let originalPostRef = post.originalPost
            let postBoostedByRef = post.boostedBy
            let hasOriginalPost = originalPostRef != nil
            let hasBoostedBy = (boostedBy ?? postBoostedByRef) != nil
            let hasReplyInfo = replyInfo != nil
            DebugLog.verbose("🔍 [PostCardView] Banner state for post \(post.id):")
            DebugLog.verbose("  - hasOriginalPost: \(hasOriginalPost)")
            DebugLog.verbose("  - hasBoostedBy: \(hasBoostedBy) (boostedBy param: \(boostedBy ?? "nil"), post.boostedBy: \(postBoostedByRef ?? "nil"))")
            DebugLog.verbose("  - hasReplyInfo: \(hasReplyInfo)")
            if hasOriginalPost {
                DebugLog.verbose("  - originalPost.id: \(originalPostRef?.id ?? "nil")")
                DebugLog.verbose("  - originalPost.content.isEmpty: \(originalPostRef?.content.isEmpty ?? true)")
            }
        }
    }

    // CRITICAL FIX: Defer logging to prevent AttributeGraph cycles from accessing post.originalPost
    private func logReplyInfo() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)  // Longer delay to ensure outside view update cycle
            // CRITICAL: Capture references once to avoid multiple synchronous accesses
            let originalPostRef = post.originalPost
            let displayPostRef = cachedDisplayPost ?? post
            let displayUsername = displayPostRef.inReplyToUsername
            let displayReplyID = displayPostRef.inReplyToID
            let logData: [String: Any] = [
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "E",
                "location": "PostCardView.swift:84",
                "message": "replyInfo check",
                "data": [
                    "postId": post.id,
                    "displayPostId": displayPostRef.id,
                    "displayUsername": displayUsername ?? "nil",
                    "displayReplyID": displayReplyID ?? "nil",
                    "postUsername": post.inReplyToUsername ?? "nil",
                    "postReplyID": post.inReplyToID ?? "nil",
                    "hasOriginalPost": originalPostRef != nil,
                ],
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            ]
        let logPath = "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log"
        if let jsonData = try? JSONSerialization.data(withJSONObject: logData),
            let jsonString = String(data: jsonData, encoding: .utf8)
        {
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write((jsonString + "\n").data(using: .utf8)!)
                try? fileHandle.close()
            } else {
                FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.write((jsonString + "\n").data(using: .utf8)!)
                    try? fileHandle.close()
                    }
                }
            }
        }
    }

    // Helper to log boost banner info
    private func logBoostBanner(
        boostHandle: String?, postBoostedBy: String?, finalBoostedBy: String?
    ) {
        let logData: [String: Any] = [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "F",
            "location": "PostCardView.swift:197",
            "message": "boost banner check",
            "data": [
                "postId": post.id,
                "boostedBy": boostedBy ?? "nil",
                "postBoostedBy": postBoostedBy ?? "nil",
                "finalBoostedBy": finalBoostedBy ?? "nil",
                "boostHandle": boostHandle ?? "nil",
                "hasOriginalPost": cachedDisplayPost != nil && cachedDisplayPost?.id != post.id,
                "authorUsername": post.authorUsername,
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
        ]
        let logPath = "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log"
        if let jsonData = try? JSONSerialization.data(withJSONObject: logData),
            let jsonString = String(data: jsonData, encoding: .utf8)
        {
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write((jsonString + "\n").data(using: .utf8)!)
                try? fileHandle.close()
            } else {
                FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.write((jsonString + "\n").data(using: .utf8)!)
                    try? fileHandle.close()
                }
            }
        }
    }

    // Convenience initializer for TimelineEntry
    init(
        entry: TimelineEntry,
        viewModel: PostViewModel? = nil,
        postActionStore: PostActionStore,
        postActionCoordinator: PostActionCoordinator? = nil,
        onPostTap: @escaping () -> Void = {},
        onParentPostTap: @escaping (Post) -> Void = { _ in },
        onAuthorTap: @escaping () -> Void = {},
        onReply: @escaping () -> Void = {},
        onRepost: @escaping () -> Void = {},
        onLike: @escaping () -> Void = {},
        onShare: @escaping () -> Void = {},
        onOpenInBrowser: @escaping () -> Void = {},
        onCopyLink: @escaping () -> Void = {},
        onReport: @escaping () -> Void = {},
        onQuote: @escaping () -> Void = {}
    ) {
        self.post = entry.post
        self.replyCount = 0
        self.repostCount = entry.post.repostCount
        self.likeCount = entry.post.likeCount
        self.isReplying = false
        self.isReposted = entry.post.isReposted
        self.isLiked = entry.post.isLiked
        self.onAuthorTap = onAuthorTap
        self.onReply = onReply
        self.onRepost = onRepost
        self.onLike = onLike
        self.onShare = onShare
        self.onOpenInBrowser = onOpenInBrowser
        self.onCopyLink = onCopyLink
        self.onReport = onReport
        self.onQuote = onQuote
        self.onMediaTap = { _ in }
        self.onPostTap = onPostTap
        self.onParentPostTap = onParentPostTap
        self.viewModel = viewModel
        self.postActionStore = postActionStore
        self.postActionCoordinator = postActionCoordinator

        // Extract boost information from TimelineEntry
        // CRITICAL: Always preserve boostedBy from both TimelineEntry and post
        // This ensures boost banners show even if one source is missing
        if case .boost(let entryBoostedBy) = entry.kind {
            // Use TimelineEntry boostedBy first, but fall back to post.boostedBy if entry is empty
            self.boostedBy = entryBoostedBy.isEmpty ? entry.post.boostedBy : entryBoostedBy
        } else {
            // Not a boost in TimelineEntry, use post.boostedBy
            // CRITICAL FIX: Don't access entry.post.originalPost here as it triggers objectWillChange
            // Cache will be initialized in onAppear
                self.boostedBy = entry.post.boostedBy
            }
        
        // CRITICAL FIX: Initialize cache synchronously to prevent accessing post.originalPost during rendering
        // For boost posts, initialize to originalPost so content appears immediately
        // Safe to access originalPost in initializer (not in view update cycle)
        let initialDisplayPost: Post
        let initialPlatform: SocialPlatform
        if let originalPost = entry.post.originalPost {
            // Boost post - use original for display
            initialDisplayPost = originalPost
            initialPlatform = originalPost.platform
        } else {
            // Regular post - use post itself
            initialDisplayPost = entry.post
            initialPlatform = entry.post.platform
        }
        _cachedDisplayPost = State(initialValue: initialDisplayPost)
        _cachedPlatform = State(initialValue: initialPlatform)
        
        // Initialize boost handle with proper fallback logic
        let initialBoostHandle: String?
        if entry.post.originalPost != nil {
            // This is a boost - determine who boosted it
            if let boostedBy = self.boostedBy, !boostedBy.isEmpty {
                initialBoostHandle = boostedBy
            } else if let boostedBy = entry.post.boostedBy, !boostedBy.isEmpty {
                initialBoostHandle = boostedBy
            } else if !entry.post.authorUsername.isEmpty {
                // Fallback: use the post author (the person who boosted)
                initialBoostHandle = entry.post.authorUsername
            } else if entry.post.id.hasPrefix("repost-") {
                // Extract from repost ID format
                let components = entry.post.id.split(separator: "-", maxSplits: 2)
                initialBoostHandle = components.count >= 2 ? String(components[1]) : "Someone"
            } else {
                initialBoostHandle = "Someone"
            }
        } else if let boostedBy = self.boostedBy, !boostedBy.isEmpty {
            // Not a boost structurally, but has boostedBy metadata
            initialBoostHandle = boostedBy
        } else if let boostedBy = entry.post.boostedBy, !boostedBy.isEmpty {
            initialBoostHandle = boostedBy
        } else {
            initialBoostHandle = nil
        }

        if let handle = initialBoostHandle {
            _cachedBoostHandle = State(initialValue: handle)
        }
        
        // Initialize booster emoji map for boost banner
        _cachedBoosterEmojiMap = State(initialValue: entry.post.boosterEmojiMap)
        
        // Initialize reply info if this is a reply
        if let originalPost = entry.post.originalPost {
            // For boosts, check original post for reply info
            if let username = originalPost.inReplyToUsername, !username.isEmpty {
                _cachedReplyInfo = State(initialValue: (username, originalPost.inReplyToID, originalPost.platform))
            } else if let username = entry.post.inReplyToUsername, !username.isEmpty {
                _cachedReplyInfo = State(initialValue: (username, entry.post.inReplyToID, entry.post.platform))
            } else if let replyId = originalPost.inReplyToID ?? entry.post.inReplyToID {
                _cachedReplyInfo = State(initialValue: ("someone", replyId, originalPost.platform))
            }
        } else if let username = entry.post.inReplyToUsername, !username.isEmpty {
            _cachedReplyInfo = State(initialValue: (username, entry.post.inReplyToID, entry.post.platform))
        } else if let replyId = entry.post.inReplyToID {
            _cachedReplyInfo = State(initialValue: ("someone", replyId, entry.post.platform))
        }
        
        // Initialize attachments
        if let originalPost = entry.post.originalPost, !originalPost.attachments.isEmpty {
            _cachedAttachments = State(initialValue: originalPost.attachments)
        } else {
            _cachedAttachments = State(initialValue: entry.post.attachments)
        }
        
        // Initialize poll
        if let originalPost = entry.post.originalPost {
            _cachedPoll = State(initialValue: originalPost.poll)
        } else {
            _cachedPoll = State(initialValue: entry.post.poll)
        }
    }

    // Original initializer for backward compatibility
    init(
        post: Post,
        replyCount: Int,
        repostCount: Int,
        likeCount: Int,
        isReplying: Bool,
        isReposted: Bool,
        isLiked: Bool,
        onAuthorTap: @escaping () -> Void,
        onReply: @escaping () -> Void,
        onRepost: @escaping () -> Void,
        onLike: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onQuote: @escaping () -> Void = {},
        onMediaTap: @escaping (Post.Attachment) -> Void,
        onOpenInBrowser: @escaping () -> Void,
        onCopyLink: @escaping () -> Void,
        onReport: @escaping () -> Void,
        onPostTap: @escaping () -> Void,
        onParentPostTap: @escaping (Post) -> Void = { _ in },
        viewModel: PostViewModel? = nil,
        postActionStore: PostActionStore,
        postActionCoordinator: PostActionCoordinator? = nil
    ) {
        self.post = post
        self.replyCount = replyCount
        self.repostCount = repostCount
        self.likeCount = likeCount
        self.isReplying = isReplying
        self.isReposted = isReposted
        self.isLiked = isLiked
        self.onAuthorTap = onAuthorTap
        self.onReply = onReply
        self.onRepost = onRepost
        self.onLike = onLike
        self.onShare = onShare
        self.onQuote = onQuote
        self.onMediaTap = onMediaTap
        self.onOpenInBrowser = onOpenInBrowser
        self.onCopyLink = onCopyLink
        self.onReport = onReport
        self.onPostTap = onPostTap
        self.onParentPostTap = onParentPostTap
        self.viewModel = viewModel
        // Use post.boostedBy if available, otherwise nil
        self.boostedBy = post.boostedBy
        self.postActionStore = postActionStore
        self.postActionCoordinator = postActionCoordinator
        
        // CRITICAL FIX: Initialize cache synchronously to prevent accessing post.originalPost during rendering
        // For boost posts, initialize to originalPost so content appears immediately
        // Safe to access originalPost in initializer (not in view update cycle)
        let initialDisplayPost: Post
        let initialPlatform: SocialPlatform
        if let originalPost = post.originalPost {
            // Boost post - use original for display
            initialDisplayPost = originalPost
            initialPlatform = originalPost.platform
        } else {
            // Regular post - use post itself
            initialDisplayPost = post
            initialPlatform = post.platform
        }
        _cachedDisplayPost = State(initialValue: initialDisplayPost)
        _cachedPlatform = State(initialValue: initialPlatform)
        
        // Initialize boost handle with proper fallback logic
        let initialBoostHandle: String?
        if post.originalPost != nil {
            // This is a boost - determine who boosted it
            if let boostedBy = self.boostedBy, !boostedBy.isEmpty {
                initialBoostHandle = boostedBy
            } else if let boostedBy = post.boostedBy, !boostedBy.isEmpty {
                initialBoostHandle = boostedBy
            } else if !post.authorUsername.isEmpty {
                // Fallback: use the post author (the person who boosted)
                initialBoostHandle = post.authorUsername
            } else if post.id.hasPrefix("repost-") {
                // Extract from repost ID format
                let components = post.id.split(separator: "-", maxSplits: 2)
                initialBoostHandle = components.count >= 2 ? String(components[1]) : "Someone"
            } else {
                initialBoostHandle = "Someone"
            }
        } else if let boostedBy = self.boostedBy, !boostedBy.isEmpty {
            // Not a boost structurally, but has boostedBy metadata
            initialBoostHandle = boostedBy
        } else if let boostedBy = post.boostedBy, !boostedBy.isEmpty {
            initialBoostHandle = boostedBy
        } else {
            initialBoostHandle = nil
        }

        if let handle = initialBoostHandle {
            _cachedBoostHandle = State(initialValue: handle)
        }
        
        // Initialize booster emoji map for boost banner
        _cachedBoosterEmojiMap = State(initialValue: post.boosterEmojiMap)
        
        // Initialize reply info if this is a reply
        if let originalPost = post.originalPost {
            // For boosts, check original post for reply info
            if let username = originalPost.inReplyToUsername, !username.isEmpty {
                _cachedReplyInfo = State(initialValue: (username, originalPost.inReplyToID, originalPost.platform))
            } else if let username = post.inReplyToUsername, !username.isEmpty {
                _cachedReplyInfo = State(initialValue: (username, post.inReplyToID, post.platform))
            } else if let replyId = originalPost.inReplyToID ?? post.inReplyToID {
                _cachedReplyInfo = State(initialValue: ("someone", replyId, originalPost.platform))
            }
        } else if let username = post.inReplyToUsername, !username.isEmpty {
            _cachedReplyInfo = State(initialValue: (username, post.inReplyToID, post.platform))
        } else if let replyId = post.inReplyToID {
            _cachedReplyInfo = State(initialValue: ("someone", replyId, post.platform))
        }
        
        // Initialize attachments
        if let originalPost = post.originalPost, !originalPost.attachments.isEmpty {
            _cachedAttachments = State(initialValue: originalPost.attachments)
        } else {
            _cachedAttachments = State(initialValue: post.attachments)
        }
        
        // Initialize poll
        if let originalPost = post.originalPost {
            _cachedPoll = State(initialValue: originalPost.poll)
        } else {
            _cachedPoll = State(initialValue: post.poll)
        }
    }

    // Helper to get boost handle for banner
    // CRITICAL FIX: Only use cached value to prevent AttributeGraph cycles
    private var boostHandleToShow: String? {
        // Always use cached value - it's updated in onAppear/onChange
        // Return nil if cached value is empty string
        guard let cached = cachedBoostHandle, !cached.isEmpty else {
        return nil
        }
        return cached
    }

    // Computed property for boost banner to simplify body
    // CRITICAL FIX: Use cached platform to prevent AttributeGraph cycles
    @ViewBuilder
    private var boostBannerView: some View {
        if let handleToShow = boostHandleToShow, !handleToShow.isEmpty {
            BoostBanner(handle: handleToShow, platform: displayPlatform, emojiMap: cachedBoosterEmojiMap)
                .padding(.horizontal, 12)  // Apple standard: 12pt for content
                .padding(.vertical, 6)  // Adequate touch target
                .frame(maxWidth: .infinity, alignment: .leading)  // Ensure full width visibility
                .onAppear {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 10_000_000)  // Defer to avoid cycles
                    // CRITICAL FIX: Use cached boost handle instead of accessing post.boostedBy synchronously
                    let finalBoostedBy = cachedBoostHandle ?? handleToShow
                    DebugLog.verbose("🔍 [PostCardView] Rendering boost banner for post \(post.id) with handle: \(handleToShow)")
                    logBoostBanner(
                        boostHandle: handleToShow, postBoostedBy: cachedBoostHandle,
                        finalBoostedBy: finalBoostedBy)
                    }
                }
        } else {
            EmptyView()
        }
    }

    // MARK: - View Components (broken down to help type checker)
    
    @ViewBuilder
    private var bannerSection: some View {
            // Boost banner if this post was boosted/reposted
        // CRITICAL FIX: Use cached platform to prevent AttributeGraph cycles
            if let handleToShow = boostHandleToShow, !handleToShow.isEmpty {
            BoostBanner(handle: handleToShow, platform: displayPlatform, emojiMap: cachedBoosterEmojiMap)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                    .onAppear {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000)  // Longer delay to ensure outside view update cycle
                        // CRITICAL FIX: Use cached boost handle instead of accessing post.boostedBy synchronously
                        let finalBoostedBy = cachedBoostHandle ?? handleToShow
                        DebugLog.verbose("🔍 [PostCardView] Rendering boost banner for post \(post.id) with handle: \(handleToShow)")
                        logBoostBanner(
                            boostHandle: handleToShow, postBoostedBy: cachedBoostHandle,
                            finalBoostedBy: finalBoostedBy)
                    }
                    }
            }

            // Expanding reply banner if this post is a reply
            if let replyInfo = replyInfo {
                ExpandingReplyBanner(
                    username: replyInfo.username,
                    network: replyInfo.platform,
                    parentId: replyInfo.id,
                    initialParent: nil,
                    isExpanded: $isReplyBannerExpanded,
                    onBannerTap: { bannerWasTapped = true },
                    onParentPostTap: { parentPost in
                    onParentPostTap(parentPost)
                }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(displayPost.id + "_reply_banner")
                .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)  // Longer delay to ensure outside view update cycle
                    DebugLog.verbose("[PostCardView] 🎯 Rendering ExpandingReplyBanner for post \(post.id) with username: \(replyInfo.username)")
                    logReplyInfo()
                }
            }
        }
    }
    
    @ViewBuilder
    private var contentSection: some View {
        PostAuthorView(post: displayPost, onAuthorTap: onAuthorTap)
            .padding(.horizontal, 12)
        
            displayPost.contentView(
                lineLimit: nil,
            showLinkPreview: true,
                font: .body,
                onQuotePostTap: { quotedPost in
                onParentPostTap(quotedPost)
                },
            allowTruncation: false
            )
        .padding(.horizontal, 8)
            .padding(.top, 4)
        // CRITICAL FIX: Removed onAppear callback that was accessing post.originalPost
        // This was causing AttributeGraph cycles. Debug logging moved to deferred Task.
        
        // CRITICAL FIX: Use cached poll instead of accessing displayPost.poll during rendering
        if let poll = cachedPoll {
            PostPollView(
                poll: poll,
                allowsVoting: true,
                onVote: { optionIndexes in
                    Task {
                        do {
                            try await serviceManager.voteInPoll(post: displayPost, choices: optionIndexes)
                        } catch {
                            DebugLog.verbose("❌ Failed to vote: \(error.localizedDescription)")
                        }
                    }
                }
            )
            .padding(.horizontal, 12)
        }
    }
    
    @ViewBuilder
    private var mediaSection: some View {
        // CRITICAL FIX: Only use cached attachments to prevent accessing displayPost.attachments synchronously
        // This prevents AttributeGraph cycles when displayPost is originalPost
        let attachmentsToShow = cachedAttachments
            if !attachmentsToShow.isEmpty {
                let hasGIF = attachmentsToShow.contains { $0.type == .animatedGIF }
                let mediaMaxHeight = hasGIF ? min(UIScreen.main.bounds.height * 0.7, 800) : 600

                UnifiedMediaGridView(attachments: attachmentsToShow, maxHeight: mediaMaxHeight)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .clipped()
                    .onAppear {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000)  // Longer delay to ensure outside view update cycle
                        DebugLog.verbose("[PostCardView] 📎 Displaying \(attachmentsToShow.count) attachments for post \(post.id)")
                        for (index, att) in attachmentsToShow.enumerated() {
                            DebugLog.verbose("[PostCardView]   Attachment \(index): type=\(att.type), url=\(att.url)")
                        }
                    }
                }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            bannerSection
            contentSection
            mediaSection
            actionBarView
                .padding(.horizontal, 12)
                .padding(.top, 2)
        }
        .padding(.horizontal, 12)  // Reduced from 16 to give more space for content
        .padding(.vertical, 12)  // Apple standard: 12pt container padding
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture {
            // Only handle tap if banner wasn't tapped
            if !bannerWasTapped {
                onPostTap()
            }
            bannerWasTapped = false
        }
        .onAppear {
            // CRITICAL FIX: Update cache on appear to ensure correct values
            // Cache is initialized to post in initializer, but may need to be updated to originalPost
            // Use Task with longer delay to ensure we're completely outside the rendering cycle
            // CRITICAL: Only update in onAppear, not onChange, to prevent cycles
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2 seconds delay - longer to ensure outside cycle
                guard !isUpdatingCache else { return }
                updateCachedValues()
            }
        }
        .onChange(of: post.id) { _ in
            // CRITICAL FIX: Update cache when post changes (e.g., originalPost is set)
            // But defer it to prevent AttributeGraph cycles
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2 seconds delay
                guard !isUpdatingCache else { return }
                updateCachedValues()
            }
        }
        // CRITICAL FIX: Removed onChange modifiers for post.originalPost that were causing AttributeGraph cycles
        // Instead, we watch post.id and update cache asynchronously when it changes
        // MARK: - Accessibility Support
        .accessibilityElement(children: .contain)
        .accessibilityLabel(postAccessibilityLabel)
        .accessibilityHint("Double tap to view full post and replies")
        .accessibilityAction(named: "Reply") {
            onReply()
        }
        .accessibilityAction(named: "Repost") {
            onRepost()
        }
        .accessibilityAction(named: "Like") {
            onLike()
        }
        .accessibilityAction(named: "Share") {
            onShare()
        }
        .sheet(isPresented: $showListSelection) {
            if let account = serviceManager.mastodonAccounts.first {
                ListSelectionView(accountToLink: post.authorId, platformAccount: account)
                    .environmentObject(serviceManager)
            }
        }
    }

    // MARK: - Action Bar View

    @ViewBuilder
    private var actionBarView: some View {
        if FeatureFlagManager.isEnabled(.postActionsV2),
            let coordinator = postActionCoordinator
        {
            ActionBarV2(
                post: displayPost,
                store: postActionStore,
                coordinator: coordinator,
                onAction: { action in
                    switch action {
                    case .reply:
                        onReply()
                    case .repost:
                        onRepost()
                    case .like:
                        onLike()
                    case .share:
                        onShare()
                    case .quote:
                        onQuote()
                    case .follow:
                        if let viewModel = viewModel {
                            Task { await viewModel.followUser() }
                        }
                    case .mute:
                        if let viewModel = viewModel {
                            Task { await viewModel.muteUser() }
                        }
                    case .block:
                        if let viewModel = viewModel {
                            Task { await viewModel.blockUser() }
                        }
                    case .addToList:
                        showListSelection = true
                    case .openInBrowser:
                        onOpenInBrowser()
                    case .copyLink:
                        onCopyLink()
                    case .shareSheet:
                        onShare()
                    case .report:
                        onReport()
                    @unknown default:
                        break
                    }
                },
                onMenuOpen: {
                    Task {
                        await serviceManager.refreshRelationshipStateForMenu(for: displayPost)
                    }
                }
            )
        } else {
            ActionBar(
                post: displayPost,
                onAction: { action in
                    switch action {
                    case .reply:
                        onReply()
                    case .repost:
                        onRepost()
                    case .like:
                        onLike()
                    case .share:
                        onShare()
                    case .quote:
                        onQuote()
                    case .follow:
                        if let viewModel = viewModel {
                            Task { await viewModel.followUser() }
                        }
                    case .mute:
                        if let viewModel = viewModel {
                            Task { await viewModel.muteUser() }
                        }
                    case .block:
                        if let viewModel = viewModel {
                            Task { await viewModel.blockUser() }
                        }
                    case .addToList:
                        showListSelection = true
                    case .openInBrowser:
                        onOpenInBrowser()
                    case .copyLink:
                        onCopyLink()
                    case .shareSheet:
                        onShare()
                    case .report:
                        onReport()
                    @unknown default:
                        break
                    }
                },
                onMenuOpen: {
                    Task {
                        await serviceManager.refreshRelationshipStateForMenu(for: displayPost)
                    }
                }
            )
        }
    }

    // MARK: - Accessibility Helpers

    /// Creates a comprehensive accessibility label for the post
    private var postAccessibilityLabel: String {
        var components: [String] = []

        // Boost information
        if let boostedBy = boostedBy {
            components.append("Reposted by \(boostedBy)")
        }

        // Author and timestamp
        components.append(
            "Post by \(displayPost.authorName), \(formatAccessibilityTimestamp(displayPost.createdAt))"
        )

        // Content
        let cleanContent = displayPost.content.replacingOccurrences(of: "\n", with: " ")
        if !cleanContent.isEmpty {
            components.append("Content: \(cleanContent)")
        }

        // Media count
        if !displayPost.attachments.isEmpty {
            let mediaCount = displayPost.attachments.count
            let mediaType = displayPost.attachments.first?.type == .image ? "image" : "media"
            components.append("\(mediaCount) \(mediaType)\(mediaCount > 1 ? "s" : "") attached")
        }

        // Interaction counts
        var interactions: [String] = []
        if replyCount > 0 {
            interactions.append("\(replyCount) repl\(replyCount == 1 ? "y" : "ies")")
        }
        if repostCount > 0 {
            interactions.append("\(repostCount) repost\(repostCount == 1 ? "" : "s")")
        }
        if likeCount > 0 {
            interactions.append("\(likeCount) like\(likeCount == 1 ? "" : "s")")
        }

        if !interactions.isEmpty {
            components.append(interactions.joined(separator: ", "))
        }

        // User's interaction state
        var userStates: [String] = []
        if isLiked {
            userStates.append("liked by you")
        }
        if isReposted {
            userStates.append("reposted by you")
        }
        if isReplying {
            userStates.append("reply in progress")
        }

        if !userStates.isEmpty {
            components.append(userStates.joined(separator: ", "))
        }

        return components.joined(separator: ". ")
    }

    /// Formats timestamp for accessibility
    private func formatAccessibilityTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Preview
struct PostCardView_Previews: PreviewProvider {
    static var previews: some View {
        let store = PostActionStore()

        VStack(spacing: 16) {
            // Simple test - basic post using TimelineEntry
            PostCardView(
                entry: TimelineEntry(
                    id: "1",
                    kind: .normal,
                    post: Post.samplePosts[0],
                    createdAt: Date()
                ),
                viewModel: nil,
                postActionStore: store,
                onPostTap: {}
            )
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .previewLayout(.sizeThatFits)
    }
}

struct ListSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var serviceManager: SocialServiceManager
    let accountToLink: String
    let platformAccount: SocialAccount

    @State private var lists: [MastodonList] = []
    @State private var isLoading = true
    @State private var error: String? = nil

    var body: some View {
        NavigationView {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                } else if lists.isEmpty {
                    Text("No lists found")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(lists) { list in
                        Button(action: { addToList(list) }) {
                            HStack {
                                Text(list.title)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                fetchLists()
            }
        }
    }

    private func fetchLists() {
        isLoading = true
        Task {
            do {
                let fetchedLists = try await serviceManager.fetchMastodonLists(
                    account: platformAccount)
                await MainActor.run {
                    self.lists = fetchedLists
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func addToList(_ list: MastodonList) {
        isLoading = true
        Task {
            do {
                try await serviceManager.addAccountToMastodonList(
                    listId: list.id,
                    accountToLink: accountToLink,
                    account: platformAccount
                )
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}
