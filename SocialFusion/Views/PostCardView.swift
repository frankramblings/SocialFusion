import Foundation
import LinkPresentation  // For link previews
// Forward imports
import SwiftUI

// Local implementation of PreviewLinkSelection to avoid import issues
private class PreviewLinkSelection: ObservableObject {
    static let shared = PreviewLinkSelection()

    /// Dictionary to store which links should be previewed for each post
    @Published private var selectedLinksForPosts: [String: URL] = [:]

    /// Dictionary to track if link preview is disabled for specific posts
    @Published private var disabledPreviewsForPosts: Set<String> = []

    private init() {}

    /// Set the selected link to preview for a post
    func setSelectedLink(url: URL, for postId: String) {
        selectedLinksForPosts[postId] = url
        // Enable previews when a specific link is selected
        disabledPreviewsForPosts.remove(postId)
    }

    /// Get the selected link for preview for a post
    func getSelectedLink(for postId: String) -> URL? {
        return selectedLinksForPosts[postId]
    }

    /// Disable link previews for a specific post
    func disablePreviews(for postId: String) {
        disabledPreviewsForPosts.insert(postId)
        // Remove any selected link
        selectedLinksForPosts.removeValue(forKey: postId)
    }

    /// Enable link previews for a specific post
    func enablePreviews(for postId: String) {
        disabledPreviewsForPosts.remove(postId)
    }

    /// Check if previews are disabled for a specific post
    func arePreviewsDisabled(for postId: String) -> Bool {
        return disabledPreviewsForPosts.contains(postId)
    }

    /// Clear all selections for a post
    func clearSelections(for postId: String) {
        selectedLinksForPosts.removeValue(forKey: postId)
        disabledPreviewsForPosts.remove(postId)
    }
}

// Local implementation of LinkPreviewSelector
private struct LinkPreviewSelector: View {
    let links: [URL]
    let postId: String
    @State private var selectedURL: URL?
    @State private var showMenu = false
    @State private var arePreviewsDisabled = false

    var body: some View {
        VStack(alignment: .leading) {
            if !links.isEmpty && !arePreviewsDisabled {
                HStack {
                    Text("Link Preview")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Menu {
                        // Option to disable all previews
                        Button(
                            role: .destructive,
                            action: {
                                disablePreviews()
                            }
                        ) {
                            Label("Disable Preview", systemImage: "eye.slash")
                        }

                        Divider()

                        // For each link, create a menu option
                        ForEach(links, id: \.absoluteString) { link in
                            Button(action: {
                                selectLink(link)
                            }) {
                                HStack {
                                    if selectedURL == link {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(link.host ?? link.absoluteString)
                                        .lineLimit(1)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if let selectedURL = selectedURL, let host = selectedURL.host {
                                Text(host)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(6)
            }
        }
        .onAppear {
            // Check if we have a previously selected URL for this post
            if let existing = PreviewLinkSelection.shared.getSelectedLink(for: postId) {
                self.selectedURL = existing
            } else if !links.isEmpty {
                // Default to the first link if none is selected
                self.selectedURL = links.first
                PreviewLinkSelection.shared.setSelectedLink(url: links.first!, for: postId)
            }

            // Check if previews are disabled for this post
            self.arePreviewsDisabled = PreviewLinkSelection.shared.arePreviewsDisabled(for: postId)
        }
    }

    private func selectLink(_ url: URL) {
        self.selectedURL = url
        PreviewLinkSelection.shared.setSelectedLink(url: url, for: postId)
    }

    private func disablePreviews() {
        self.arePreviewsDisabled = true
        PreviewLinkSelection.shared.disablePreviews(for: postId)
    }
}

// Local URL service wrapper for link detection
private struct URLServiceWrapper {
    static let shared = URLServiceWrapper()

    private init() {}

    func isBlueskyPostURL(_ url: URL) -> Bool {
        guard let host = url.host else { return false }

        // Match bsky.app and bsky.social URLs
        let isBlueskyDomain = host.contains("bsky.app") || host.contains("bsky.social")

        // Check if it's a post URL pattern: /profile/{username}/post/{postId}
        let path = url.path
        let isPostURL = path.contains("/profile/") && path.contains("/post/")

        return isBlueskyDomain && isPostURL
    }

    func isMastodonPostURL(_ url: URL) -> Bool {
        guard let host = url.host else { return false }

        // Check for common Mastodon instances or pattern
        let isMastodonInstance =
            host.contains("mastodon.social") || host.contains("mastodon.online")
            || host.contains("mas.to") || host.contains("mastodon.world")
            || host.contains(".social")

        // Check if it matches Mastodon post URL pattern: /@username/postID
        let path = url.path
        let isPostURL = path.contains("/@") && path.split(separator: "/").count >= 3

        return isMastodonInstance && isPostURL
    }
}

/// Post action types
enum PostAction {
    case reply
    case repost
    case like
    case share
}

// Using Color extensions from Color+Theme.swift
@available(iOS 16.0, *)
extension Color {
    static var cardBackground: Color {
        Color("CardBackground")
    }

    static var subtleBorder: Color {
        Color.gray.opacity(0.2)
    }

    static var elementBackground: Color {
        Color.white.opacity(0.07)
    }

    static var elementBorder: Color {
        Color.white.opacity(0.15)
    }

    static var elementShadow: Color {
        Color.white.opacity(0.05)
    }

    static func adaptiveElementBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.03)
    }

    static func adaptiveElementBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
    }
}

/// Rounded card with border/shadow for timeline posts.
struct TimelineCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.subtleBorder, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}

/// A view that displays a post in the timeline exactly matching the reference design
struct PostCardView: View {
    let post: Post
    @State private var showDetailView = false
    @State private var showParentPost = false
    @State private var parentPost: Post? = nil
    @State private var isParentExpanded = false
    @State private var isLoadingParent = false
    @EnvironmentObject var serviceManager: SocialServiceManager
    @Environment(\.colorScheme) private var colorScheme

    // Bluesky blue color
    private let blueskyBlue = Color(red: 0, green: 122 / 255, blue: 255 / 255)

    // Mastodon purple color
    private let mastodonPurple = Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)

    // Animation duration for sliding the parent post
    private let animationDuration: Double = 0.35

    // Formatter for relative timestamps
    private func formatRelativeTime(from date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date, to: now)

        if let year = components.year, year > 0 {
            return "\(year)y"
        } else if let month = components.month, month > 0 {
            return "\(month)mo"
        } else if let day = components.day, day > 0 {
            if day < 7 {
                return "\(day)d"
            } else {
                let week = day / 7
                return "\(week)w"
            }
        } else if let hour = components.hour, hour > 0 {
            return "\(hour)h"
        } else if let minute = components.minute, minute > 0 {
            return "\(minute)m"
        } else {
            return "now"
        }
    }

    // Determine which post to show (original or boosted)
    private var displayPost: Post {
        // If this is a boosted post with an original post, use that
        if let originalPost = post.originalPost {
            return originalPost
        }
        return post
    }

    // Determine which parent post to use (from post.parent or our local state)
    private var effectiveParentPost: Post? {
        return displayPost.parent ?? parentPost
    }

    var body: some View {
        TimelineCard {
            VStack(alignment: .leading, spacing: 0) {
                // Boost/Repost banner if applicable
                if post.boostedBy != nil {
                    BoostBannerView(handle: post.boostedBy ?? "", platform: post.platform)
                        .padding(.bottom, 4)
                }

                // Reply section with expandable parent
                if displayPost.inReplyToID != nil {
                    let _ = print(
                        "📱 Found reply post: platform=\(displayPost.platform), postID=\(displayPost.id), inReplyToID=\(displayPost.inReplyToID ?? "nil")"
                    )
                    VStack(alignment: .leading, spacing: 0) {
                        // Reply banner
                        replyBannerView

                        // Add spacing between reply banner and parent post
                        if isParentExpanded {
                            Spacer()
                                .frame(height: 6)
                        }

                        // Parent post content (slides up from behind the main post)
                        if let parent = effectiveParentPost {
                            ParentPostContainer(
                                parent: parent,
                                isExpanded: isParentExpanded,
                                onTap: { showParentPost = true }
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        } else if isLoadingParent {
                            // Loading state for parent post
                            if isParentExpanded {
                                LoadingParentView()
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                    }
                    .padding(.bottom, isParentExpanded ? 12 : 8)
                    .clipped()
                }

                // Main post content with visual distinction
                VStack(alignment: .leading, spacing: 10) {
                    // Post header with author info
                    HStack(alignment: .center) {
                        // Profile image with platform indicator
                        PostAuthorImageView(
                            authorProfilePictureURL: displayPost.authorProfilePictureURL,
                            platform: displayPost.platform,
                            size: 44
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            // Author name
                            Text(displayPost.authorName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)

                            // Username
                            HStack(spacing: 4) {
                                Text("@\(displayPost.authorUsername)")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        // Timestamp with chevron
                        HStack(spacing: 2) {
                            Text(formatRelativeTime(from: displayPost.createdAt))
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Post content - ensure we show content even if it's a reply
                    // Use contentView instead of directly displaying content to handle HTML in Mastodon posts
                    displayPost.contentView(lineLimit: nil, showLinkPreview: true)
                        .font(.system(size: 16))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)

                    // Media attachments if any
                    if !displayPost.attachments.isEmpty {
                        mediaSection(for: displayPost)
                            .padding(.top, 8)
                    }

                    // Action bar
                    ActionBar(
                        isLiked: displayPost.isLiked,
                        isReposted: displayPost.isReposted,
                        likeCount: displayPost.likeCount,
                        repostCount: displayPost.repostCount,
                        replyCount: 0,
                        onAction: handleAction
                    )
                }
                // Add padding when parent is expanded but no visual box
                .padding(.top, isParentExpanded ? 8 : 0)
            }
        }
        .onTapGesture {
            showDetailView = true
        }
        .sheet(isPresented: $showDetailView) {
            NavigationView {
                PostDetailView(post: displayPost)
            }
        }
        .sheet(isPresented: $showParentPost) {
            if let parent = effectiveParentPost {
                NavigationView {
                    PostDetailView(post: parent)
                }
            }
        }
        .onAppear {
            // Pre-fetch parent post information if this is a reply
            if displayPost.inReplyToID != nil && effectiveParentPost == nil {
                // Print debug information
                print(
                    "DEBUG: Reply post - platform: \(displayPost.platform), inReplyToID: \(displayPost.inReplyToID ?? "nil"), inReplyToUsername: \(displayPost.inReplyToUsername ?? "nil")"
                )

                if let parent = displayPost.parent {
                    print("DEBUG: Parent post is already available: \(parent.authorUsername)")
                } else {
                    print("DEBUG: No parent post available, will attempt to fetch")

                    // For Mastodon posts, immediately start pre-loading parent to ensure instant availability
                    // when the user taps the reply banner - crucial for UX
                    if displayPost.platform == .mastodon, let replyToID = displayPost.inReplyToID {
                        Task(priority: .userInitiated) {
                            print(
                                "📱 Preemptively loading Mastodon parent post on appear: \(replyToID)"
                            )
                            await fetchMastodonParentPost(replyToID: replyToID)
                        }
                    } else if let replyToID = displayPost.inReplyToID {
                        Task {
                            // Standard pre-loading for other platforms
                            await fetchParentPost(replyToID: replyToID)
                        }
                    }
                }
            }
        }
    }

    // Helper function to extract username from replyToID based on platform
    private func extractReplyUsername(from replyID: String?, platform: SocialPlatform) -> String {
        guard replyID != nil else { return "..." }

        // First check if the post has a stored reply username
        if let storedUsername = displayPost.inReplyToUsername, !storedUsername.isEmpty {
            print("📱 Using stored username for reply banner: \(storedUsername)")
            return storedUsername
        }

        // If we have a parent post, use its username
        if let parentUsername = effectiveParentPost?.authorUsername, !parentUsername.isEmpty {
            print("📱 Using parent post username for reply banner: \(parentUsername)")
            return parentUsername
        }

        // If we're currently loading the parent post, show loading indicator
        if isLoadingParent {
            return "..."
        }

        // Platform-specific fallbacks to avoid showing "user"
        if platform == .mastodon, let replyID = replyID {
            // For Mastodon, try to extract account ID from mentions if possible
            if let firstMention = displayPost.mentions.first {
                print("📱 Using first mention as fallback for Mastodon reply: \(firstMention)")
                return firstMention
            }

            // If no mentions, at least return a portion of the ID for debugging
            let shortenedID = String(replyID.suffix(8))
            print("📱 No username found, using shortened ID: \(shortenedID)")
            return "..."  // Still using "..." instead of raw ID in UI
        }

        // If we're here, trigger parent post preload for next time
        if let replyToID = replyID, !isLoadingParent {
            Task {
                await MainActor.run {
                    isLoadingParent = true
                }

                if platform == .mastodon {
                    await fetchMastodonParentPost(replyToID: replyToID)
                } else {
                    await fetchParentPost(replyToID: replyToID)
                }

                await MainActor.run {
                    isLoadingParent = false
                }
            }
        }

        // Generic fallback
        return "..."
    }

    // Reply banner at the top of reply posts
    private var replyBannerView: some View {
        Button(action: {
            // Toggle parent post expansion with animation
            withAnimation(.spring(response: animationDuration, dampingFraction: 0.8)) {
                isParentExpanded.toggle()
            }

            // If we're expanding and need to fetch the parent
            if isParentExpanded && effectiveParentPost == nil {
                if let replyToID = displayPost.inReplyToID {
                    Task {
                        await MainActor.run {
                            isLoadingParent = true
                        }

                        // Optimized path for Mastodon - higher priority and more aggressive fetching
                        if displayPost.platform == .mastodon {
                            await fetchMastodonParentPost(replyToID: replyToID)
                        } else {
                            await fetchParentPost(replyToID: replyToID)
                        }

                        await MainActor.run {
                            isLoadingParent = false
                        }
                    }
                }
            } else if isParentExpanded && effectiveParentPost?.content == "..." {
                // We have a placeholder parent post - fetch the full content
                if let replyToID = displayPost.inReplyToID {
                    Task {
                        await MainActor.run {
                            isLoadingParent = true
                        }

                        // Optimized path for Mastodon - higher priority and more aggressive fetching
                        if displayPost.platform == .mastodon {
                            await fetchMastodonParentPost(replyToID: replyToID)
                        } else {
                            await fetchParentPost(replyToID: replyToID)
                        }

                        await MainActor.run {
                            isLoadingParent = false
                        }
                    }
                }
            }
        }) {
            HStack {
                Image(systemName: "arrow.turn.up.left")
                    .font(.caption)
                    .foregroundColor(
                        displayPost.platform == .bluesky ? blueskyBlue : mastodonPurple)

                Text("Replying to ")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    + Text(
                        "@\(effectiveParentPost?.authorUsername ?? displayPost.inReplyToUsername ?? extractReplyUsername(from: displayPost.inReplyToID, platform: displayPost.platform))"
                    )
                    .font(.footnote)
                    .foregroundColor(
                        displayPost.platform == .bluesky ? blueskyBlue : mastodonPurple)

                Spacer()

                // Chevron indicator
                Image(systemName: isParentExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.adaptiveElementBackground(for: colorScheme))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.adaptiveElementBorder(for: colorScheme), lineWidth: 0.5)
            )
            .shadow(color: adaptiveGlowColor(opacity: 0.03), radius: 0.5, x: 0, y: 0)
            .shadow(color: adaptiveGlowColor(opacity: 0.02), radius: 1, x: 0, y: 0)
            .shadow(
                color: colorScheme == .dark ? Color.elementShadow : Color.black.opacity(0.05),
                radius: 1, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // New optimized method for Mastodon parent posts
    private func fetchMastodonParentPost(replyToID: String) async {
        print("📱 Aggressively fetching Mastodon parent post with ID: \(replyToID)")

        // First check if already preloaded via the TimelineViewModel
        if let parent = displayPost.parent, parent.content != "..." {
            print("📱 Found already preloaded Mastodon parent post in post.parent")
            await MainActor.run {
                parentPost = parent
            }
            return
        }

        // Try to use a cached value from a previous fetch
        if let parent = parentPost, parent.content != "..." {
            print("📱 Using previously fetched Mastodon parent post from local state")
            return
        }

        // Use highest priority task to ensure responsiveness
        await withTaskGroup(of: Post?.self) { group in
            // Try multiple fetch approaches in parallel for redundancy

            // Approach 1: Direct via SocialServiceManager with higher-level account handling
            group.addTask(priority: .userInitiated) {
                do {
                    let accountCopy = await MainActor.run { () -> SocialAccount? in
                        return self.serviceManager.accounts.first(where: {
                            $0.platform == .mastodon
                        })
                    }

                    if let account = accountCopy {
                        print("📱 Using Mastodon account: \(account.username) for direct fetch")
                        return try await self.serviceManager.fetchMastodonStatus(
                            id: replyToID, account: account)
                    }
                    return nil
                } catch {
                    print("📱 Error in direct Mastodon parent fetch: \(error)")
                    return nil
                }
            }

            // Approach 2: Using a Task instead of direct access to mastodonService
            group.addTask(priority: .userInitiated) {
                return await withCheckedContinuation { continuation in
                    Task {
                        // Find a Mastodon account to use
                        let accountCopy = await MainActor.run { () -> SocialAccount? in
                            return self.serviceManager.accounts.first(where: {
                                $0.platform == .mastodon
                            })
                        }

                        if let account = accountCopy {
                            do {
                                let parentPost = try await self.serviceManager.fetchMastodonStatus(
                                    id: replyToID, account: account)
                                continuation.resume(returning: parentPost)
                            } catch {
                                print("📱 Error fetching parent post: \(error)")
                                continuation.resume(returning: nil)
                            }
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }

            // Take the first successful result and update state
            for await result in group {
                if let post = result {
                    print("📱 Successfully fetched Mastodon parent post: \(post.id)")
                    await MainActor.run {
                        self.parentPost = post
                    }
                    // Break out of the loop once we have a result
                    break
                }
            }
        }
    }

    // Existing fetch parent post method for other platforms
    private func fetchParentPost(replyToID: String) async {
        print("📱 Attempting to fetch parent post with ID: \(replyToID)")
        print(
            "📱 Current post details: platform=\(displayPost.platform), id=\(displayPost.id), inReplyToUsername=\(displayPost.inReplyToUsername ?? "nil")"
        )

        // If already loaded with full content, just show it
        if let parent = effectiveParentPost, parent.content != "..." {
            print("📱 Parent post already loaded with full content, using cached version")
            print("📱 Parent post: username=\(parent.authorUsername), id=\(parent.id)")
            return
        }

        // Otherwise try to fetch it based on platform
        if displayPost.platform == .bluesky {
            print("📱 Fetching Bluesky parent post...")
            do {
                let fetchedParent = try await serviceManager.fetchBlueskyPostByID(replyToID)
                print(
                    "📱 Successfully fetched Bluesky parent post: \(fetchedParent?.id ?? "nil"), username=\(fetchedParent?.authorUsername ?? "nil")"
                )
                await MainActor.run {
                    // Use our @State property to store the parent post
                    parentPost = fetchedParent
                }
            } catch {
                print("📱 Error fetching Bluesky parent post: \(error)")
            }
        } else if displayPost.platform == .mastodon {
            print("📱 Fetching Mastodon parent post...")
            do {
                // Find the account for this platform to use for fetching
                let mastodonAccount = await MainActor.run { () -> SocialAccount? in
                    return serviceManager.accounts.first(where: { $0.platform == .mastodon })
                }

                if let account = mastodonAccount {
                    print("📱 Using Mastodon account: \(account.username) to fetch parent")
                    // Use the fetchStatus method from MastodonService
                    if let fetchedParent = try await serviceManager.fetchMastodonStatus(
                        id: replyToID, account: account)
                    {
                        print(
                            "📱 Successfully fetched Mastodon parent post: \(fetchedParent.id), username=\(fetchedParent.authorUsername)"
                        )
                        await MainActor.run {
                            // Use our @State property to store the parent post
                            parentPost = fetchedParent
                        }
                    } else {
                        print("📱 Mastodon parent post fetch returned nil")
                    }
                } else {
                    print("📱 No Mastodon account available to fetch parent post")
                }
            } catch {
                print("📱 Error fetching Mastodon parent post: \(error)")
            }
        }
    }

    // Media attachments grid
    @ViewBuilder
    private func mediaSection(for post: Post) -> some View {
        VStack {
            ForEach(post.attachments) { attachment in
                if let url = URL(string: attachment.url) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxHeight: 200)
                                .cornerRadius(12)
                        } else if phase.error != nil {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 150)
                                .cornerRadius(12)
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundColor(.secondary)
                                )
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 150)
                                .cornerRadius(12)
                                .overlay(
                                    ProgressView()
                                )
                        }
                    }
                }
            }
        }
    }

    // Handle action button taps
    private func handleAction(_ action: PostAction) {
        switch action {
        case .reply:
            showDetailView = true
        case .repost:
            Task {
                do {
                    _ = try await serviceManager.repostPost(displayPost)
                } catch {
                    print("Error reposting: \(error)")
                }
            }
        case .like:
            Task {
                do {
                    _ = try await serviceManager.likePost(displayPost)
                } catch {
                    print("Error liking: \(error)")
                }
            }
        case .share:
            // Share the post URL
            let url = URL(string: displayPost.originalURL) ?? URL(string: "https://example.com")!

            // Use MainActor for UIKit interactions
            Task { @MainActor in
                let activityController = UIActivityViewController(
                    activityItems: [url], applicationActivities: nil)

                // Present the activity view controller
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                    let window = windowScene.windows.first,
                    let rootViewController = window.rootViewController
                {
                    rootViewController.present(activityController, animated: true, completion: nil)
                }
            }
        }
    }

    // Helper function to return appropriate glow color based on color scheme
    private func adaptiveGlowColor(opacity: Double) -> Color {
        colorScheme == .dark ? Color.white.opacity(opacity) : Color.black.opacity(opacity * 0.7)  // Slightly reduced opacity for light mode
    }

    // Helper method to display links and media for a post
    @ViewBuilder
    private func displayLinksAndMedia(for post: Post) -> some View {
        VStack(spacing: 12) {
            // Extract links from the content, our improved extractLinks function
            // will now properly filter out hashtags
            if let links = extractLinks(from: post.content), !links.isEmpty {
                // Filter out any self-references
                let filteredLinks = removeSelfReferences(links: links, postURL: post.originalURL)

                if !filteredLinks.isEmpty {
                    // Show link preview selector if there are multiple links
                    if filteredLinks.count > 1 {
                        LinkPreviewSelector(links: filteredLinks, postId: post.id)
                    }

                    // If previews aren't disabled for this post
                    if !PreviewLinkSelection.shared.arePreviewsDisabled(for: post.id) {
                        // Get the selected link or default to the first one
                        let linkToPreview =
                            PreviewLinkSelection.shared.getSelectedLink(for: post.id)
                            ?? filteredLinks.first!

                        // Check if URL is a social media post URL
                        if URLServiceWrapper.shared.isBlueskyPostURL(linkToPreview)
                            || URLServiceWrapper.shared.isMastodonPostURL(linkToPreview)
                        {
                            // Show as quote post if available
                            FetchQuotePostView(url: linkToPreview)
                        } else {
                            // Show regular link preview
                            LinkPreview(url: linkToPreview)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }

            // Media attachments if any
            if !post.attachments.isEmpty {
                VStack(spacing: 8) {
                    ForEach(post.attachments) { attachment in
                        if let url = URL(string: attachment.url) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(maxHeight: 200)
                                        .cornerRadius(12)
                                        .clipped()
                                        .onTapGesture {
                                            UIApplication.shared.open(url)
                                        }
                                } else if phase.error != nil {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(height: 150)
                                        .cornerRadius(12)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .foregroundColor(.secondary)
                                        )
                                } else {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.1))
                                        .frame(height: 150)
                                        .cornerRadius(12)
                                        .overlay(
                                            ProgressView()
                                        )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Remove all hashtags from the content for link detection
    private func removeHashtagsFromContent(_ content: String) -> String {
        // Define the pattern for hashtags
        let hashtagPattern = "#[\\w]+"
        guard let regex = try? NSRegularExpression(pattern: hashtagPattern, options: []) else {
            return content
        }

        // Replace all hashtags with spaces
        return regex.stringByReplacingMatches(
            in: content,
            options: [],
            range: NSRange(location: 0, length: content.utf16.count),
            withTemplate: " ")
    }

    // Check if a URL might represent a hashtag domain
    private func isHashtagDomain(_ url: URL) -> Bool {
        guard let host = url.host else { return false }

        // Common patterns for hashtags mistakenly treated as domains
        let commonHashtags = [
            "workingclass", "laborhistory", "korea", "massacre", "gwangju",
            "imperialism", "dictatorship", "uprising", "humanrights",
            "freespeech", "demonstration", "censorship", "police",
            "actuallyautistic", "autistic",
        ]

        // Check if any of these appear in the host part of the URL
        return commonHashtags.contains { hashtag in
            host.lowercased().contains(hashtag.lowercased())
        }
    }

    // Check if a string contains a hashtag pattern
    private func containsHashtag(_ text: String) -> Bool {
        let hashtagPattern = "#[\\w]+"
        guard let regex = try? NSRegularExpression(pattern: hashtagPattern, options: []) else {
            return false
        }

        let nsRange = NSRange(location: 0, length: text.utf16.count)
        return regex.firstMatch(in: text, options: [], range: nsRange) != nil
    }
}

// Removes links that reference the post itself to avoid self-referential previews
private func removeSelfReferences(links: [URL], postURL: String) -> [URL] {
    guard let originalPostURL = URL(string: postURL) else { return links }

    return links.filter { url in
        // Don't show link preview for URLs that match the post itself
        if url.absoluteString.contains(postURL)
            || originalPostURL.absoluteString.contains(url.absoluteString)
        {
            return false
        }

        // Compare normalized host and path components to avoid previewing the post's home domain
        if let urlHost = url.host, let originalHost = originalPostURL.host,
            urlHost == originalHost
        {
            // If domains match and path contains the same ID components, likely self-reference
            let urlPath = url.path
            let originalPath = originalPostURL.path

            // Check if this is clearly the same post (containing same ID components)
            if originalPath.contains("/status/") && urlPath.contains("/status/") {
                let originalComponents = originalPath.components(separatedBy: "/")
                let urlComponents = urlPath.components(separatedBy: "/")

                // If same status ID, it's the same post
                if let originalStatusID = originalComponents.last,
                    let urlStatusID = urlComponents.last,
                    originalStatusID == urlStatusID
                {
                    return false
                }
            }

            // Similar pattern matching for Bluesky posts
            if originalPath.contains("/post/") && urlPath.contains("/post/") {
                let originalComponents = originalPath.components(separatedBy: "/")
                let urlComponents = urlPath.components(separatedBy: "/")

                if let originalIndex = originalComponents.firstIndex(of: "post"),
                    let urlIndex = urlComponents.firstIndex(of: "post"),
                    originalIndex < originalComponents.count - 1,
                    urlIndex < urlComponents.count - 1,
                    originalComponents[originalIndex + 1] == urlComponents[urlIndex + 1]
                {
                    return false
                }
            }
        }

        return true
    }
}

// Extracts links from a given string
private func extractLinks(from text: String) -> [URL]? {
    // First preprocess the text to explicitly remove all hashtags
    // This is safer than trying to filter them out after detection
    var processedText = text

    // Step 1: Replace all hashtags with spaces to prevent them from being detected as URLs
    let hashtagRegex = try? NSRegularExpression(pattern: "#\\w+", options: [])
    if let regex = hashtagRegex {
        processedText = regex.stringByReplacingMatches(
            in: processedText,
            options: [],
            range: NSRange(location: 0, length: processedText.utf16.count),
            withTemplate: ""
        )
    }

    // Step 2: Use the standard link detector on the pre-processed text
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    let matches = detector?.matches(
        in: processedText,
        options: [],
        range: NSRange(location: 0, length: processedText.utf16.count)
    )

    // Step 3: Filter the results to exclude anything that looks like a hashtag or mention
    let filteredURLs = matches?.compactMap { match -> URL? in
        guard let url = match.url else { return nil }

        // Basic validation
        let validatedURL = validateURL(url)

        // Skip anything that might be a hashtag or mention
        if isLikelyHashtagOrMention(validatedURL) {
            return nil
        }

        // For social platforms, check if this is a domain we should filter
        if let host = validatedURL.host?.lowercased() {
            // Skip common social network domains that might be showing hashtags
            if host.contains("#") || host.contains("workingclass") || host.contains("laborhistory")
                || host.contains("actuallyautistic") || host.contains("dictatorship")
                || host.contains("humanrights") || host.contains("uprising")
            {
                return nil
            }
        }

        return validatedURL
    }

    return filteredURLs
}

// More thorough check for hashtags and mentions
private func isLikelyHashtagOrMention(_ url: URL) -> Bool {
    // 1. Check for our app's custom scheme
    if url.scheme == "socialfusion" {
        return url.host == "tag" || url.host == "user"
    }

    // 2. Get the full URL string for pattern checking
    let urlString = url.absoluteString.lowercased()

    // 3. Check for obvious hashtag/mention patterns
    if urlString.contains("#") || urlString.hasPrefix("@") {
        return true
    }

    // 4. For Mastodon, specific patterns to exclude
    if url.host?.contains(".social") == true || url.host?.contains("mastodon") == true {
        // This catches cases like kolektiva.social when it's a hashtag reference
        if urlString.contains("tag/") || urlString.contains("tags/")
            || urlString.contains("hashtag/")
        {
            return true
        }
    }

    // 5. Check the path component for hashtag content
    let pathComponents = url.pathComponents
    for component in pathComponents {
        let lower = component.lowercased()
        if lower.hasPrefix("#") || lower == "tag" || lower == "tags" || lower == "trending"
            || lower == "hashtag"
        {
            return true
        }
    }

    return false
}

// Basic URL validation
private func validateURL(_ url: URL) -> URL {
    var fixedURL = url

    // Fix URLs with missing schemes
    if url.scheme == nil {
        if let urlWithScheme = URL(string: "https://" + url.absoluteString) {
            fixedURL = urlWithScheme
        }
    }

    return fixedURL
}

/// Parent post container with expansion capabilities
struct ParentPostContainer: View {
    let parent: Post
    let isExpanded: Bool
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack {
            if isExpanded {
                ParentPostPreview(post: parent, onTap: onTap)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .background(Color.adaptiveElementBackground(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    // Add a subtle border
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.adaptiveElementBorder(for: colorScheme), lineWidth: 0.5)
                    )
                    // Multiple shadows for the subtle glow effect - adapts to color scheme
                    .shadow(color: adaptiveGlowColor(opacity: 0.03), radius: 0.5, x: 0, y: 0)
                    .shadow(color: adaptiveGlowColor(opacity: 0.02), radius: 1, x: 0, y: 0)
                    .shadow(
                        color: colorScheme == .dark
                            ? Color.elementShadow : Color.black.opacity(0.05), radius: 1, y: 1)
            }
        }
        .frame(height: isExpanded ? nil : 0)
        .opacity(isExpanded ? 1 : 0)
    }

    // Helper function to return appropriate glow color based on color scheme
    private func adaptiveGlowColor(opacity: Double) -> Color {
        colorScheme == .dark ? Color.white.opacity(opacity) : Color.black.opacity(opacity * 0.7)  // Slightly reduced opacity for light mode
    }
}

/// Loading indicator for parent post
struct LoadingParentView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading parent post...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            Spacer()
        }
        .frame(height: 80)
        .background(Color.adaptiveElementBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.adaptiveElementBorder(for: colorScheme), lineWidth: 0.5)
        )
        // Multiple shadows for the subtle glow effect - adapts to color scheme
        .shadow(color: adaptiveGlowColor(opacity: 0.03), radius: 0.5, x: 0, y: 0)
        .shadow(color: adaptiveGlowColor(opacity: 0.02), radius: 1, x: 0, y: 0)
        .shadow(
            color: colorScheme == .dark ? Color.elementShadow : Color.black.opacity(0.05),
            radius: 1, y: 1)
    }

    // Helper function to return appropriate glow color based on color scheme
    private func adaptiveGlowColor(opacity: Double) -> Color {
        colorScheme == .dark ? Color.white.opacity(opacity) : Color.black.opacity(opacity * 0.7)  // Slightly reduced opacity for light mode
    }
}

/// "<user> boosted" banner with clean styling
struct BoostBannerView: View {
    let handle: String
    var platform: SocialPlatform = .bluesky  // Default to Bluesky if not specified
    @Environment(\.colorScheme) private var colorScheme

    // Platform colors
    private var platformColor: Color {
        switch platform {
        case .bluesky:
            return Color(red: 0, green: 122 / 255, blue: 255 / 255)  // Bluesky blue
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // Mastodon purple
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.2.squarepath")
                .font(.caption)
                .foregroundColor(platformColor)

            Text("\(handle) boosted")
                .font(.footnote)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.adaptiveElementBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        // Add a subtle border
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.adaptiveElementBorder(for: colorScheme), lineWidth: 0.5)
        )
        // Multiple shadows for the subtle glow effect - adapts to color scheme
        .shadow(color: adaptiveGlowColor(opacity: 0.03), radius: 0.5, x: 0, y: 0)
        .shadow(color: adaptiveGlowColor(opacity: 0.02), radius: 1, x: 0, y: 0)
        .shadow(
            color: colorScheme == .dark
                ? Color.elementShadow : Color.black.opacity(0.05), radius: 1, y: 1)
    }

    // Helper function to return appropriate glow color based on color scheme
    private func adaptiveGlowColor(opacity: Double) -> Color {
        colorScheme == .dark ? Color.white.opacity(opacity) : Color.black.opacity(opacity * 0.7)  // Slightly reduced opacity for light mode
    }
}

// Extension to apply rounded corners to specific corners only
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// Custom shape for rounded corners
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Preview
#Preview("Standard Post") {
    PostCardView(post: Post.samplePosts[0])
        .environmentObject(SocialServiceManager())
        .preferredColorScheme(.dark)
}

#Preview("Reply Post") {
    PostCardView(post: Post.samplePosts[1])
        .environmentObject(SocialServiceManager())
        .preferredColorScheme(.dark)
}

#Preview("Boosted Post") {
    PostCardView(post: Post.samplePosts[2])
        .environmentObject(SocialServiceManager())
        .preferredColorScheme(.dark)
}
