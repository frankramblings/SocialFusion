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
            .frame(maxWidth: .infinity)
    }
}

/// A view that displays a post in the timeline exactly matching the reference design
struct PostCardView: View {
    let entry: TimelineEntry
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

    // Determine which parent post to use (from post.parent or our local state)
    private var effectiveParentPost: Post? {
        return entry.post.parent ?? parentPost
    }

    var body: some View {
        TimelineCard {
            VStack(alignment: .leading, spacing: 0) {
                // Boost/Repost banner if applicable
                if case let .boost(boostedBy) = entry.kind {
                    BoostBannerView(handle: boostedBy, platform: entry.post.platform)
                        .padding(.bottom, 4)
                }

                // Reply banner if applicable
                if case .reply = entry.kind {
                    replyBannerView
                        .padding(.bottom, 4)
                }

                // Main post content with visual distinction
                VStack(alignment: .leading, spacing: 10) {
                    // Post header with author info
                    HStack(alignment: .center) {
                        // Profile image with platform indicator
                        PostAuthorImageView(
                            authorProfilePictureURL: entry.post.authorProfilePictureURL,
                            platform: entry.post.platform,
                            size: 44
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            // Author name
                            Text(entry.post.authorName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            // Username
                            HStack(spacing: 4) {
                                Text("@\(entry.post.authorUsername)")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        // Timestamp with chevron
                        HStack(spacing: 2) {
                            Text(formatRelativeTime(from: entry.createdAt))
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                    // Post content
                    Group {
                        if entry.post.platform == .bluesky {
                            entry.post.blueskyContentView()
                                .font(.system(size: 16))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        } else {
                            entry.post.contentView(lineLimit: nil, showLinkPreview: false)
                                .font(.system(size: 16))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    // --- One preview/quote card per post logic ---
                    if let quoteOrPreview = entry.post.firstQuoteOrPreviewCardView {
                        quoteOrPreview
                            .padding(.top, 8)
                    }
                    // Media attachments if any
                    if !entry.post.attachments.isEmpty {
                        UnifiedMediaGridView(attachments: entry.post.attachments, maxHeight: 400)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // Action bar (use entry.post for actions)
                    ActionBar(
                        isLiked: entry.post.isLiked,
                        isReposted: entry.post.isReposted,
                        likeCount: entry.post.likeCount,
                        repostCount: entry.post.repostCount,
                        replyCount: 0,
                        onAction: handleAction
                    )
                }
                .padding(.top, isParentExpanded ? 8 : 0)
            }
        }
        .onTapGesture {
            showDetailView = true
        }
        .sheet(isPresented: $showDetailView) {
            NavigationView {
                PostDetailView(post: entry.post)
            }
        }
        .onAppear {
            // Pre-fetch parent post information if this is a reply
            if case .reply = entry.kind, effectiveParentPost == nil {
                // Print debug information
                print(
                    "DEBUG: Reply post - platform: \(entry.post.platform), inReplyToID: \(entry.post.inReplyToID ?? "nil"), inReplyToUsername: \(entry.post.inReplyToUsername ?? "nil")"
                )

                if let parent = entry.post.parent {
                    print("DEBUG: Parent post is already available: \(parent.authorUsername)")
                } else {
                    print("DEBUG: No parent post available, will attempt to fetch")

                    // For Mastodon posts, immediately start pre-loading parent to ensure instant availability
                    // when the user taps the reply banner - crucial for UX
                    if entry.post.platform == .mastodon, let replyToID = entry.post.inReplyToID {
                        Task(priority: .userInitiated) {
                            print(
                                "📱 Preemptively loading Mastodon parent post on appear: \(replyToID)"
                            )
                            await fetchMastodonParentPost(replyToID: replyToID)
                        }
                    } else if let replyToID = entry.post.inReplyToID {
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
        if let storedUsername = entry.post.inReplyToUsername, !storedUsername.isEmpty {
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
            if let firstMention = entry.post.mentions.first {
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
                if let replyToID = entry.post.inReplyToID {
                    Task {
                        await MainActor.run {
                            isLoadingParent = true
                        }

                        // Optimized path for Mastodon - higher priority and more aggressive fetching
                        if entry.post.platform == .mastodon {
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
                if let replyToID = entry.post.inReplyToID {
                    Task {
                        await MainActor.run {
                            isLoadingParent = true
                        }

                        // Optimized path for Mastodon - higher priority and more aggressive fetching
                        if entry.post.platform == .mastodon {
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
                        entry.post.platform == .bluesky ? blueskyBlue : mastodonPurple)

                Text("Replying to ")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    + Text(
                        "@\(effectiveParentPost?.authorUsername ?? entry.post.inReplyToUsername ?? extractReplyUsername(from: entry.post.inReplyToID, platform: entry.post.platform))"
                    )
                    .font(.footnote)
                    .foregroundColor(
                        entry.post.platform == .bluesky ? blueskyBlue : mastodonPurple)

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
        if let parent = entry.post.parent, parent.content != "..." {
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
            "📱 Current post details: platform=\(entry.post.platform), id=\(entry.post.id), inReplyToUsername=\(entry.post.inReplyToUsername ?? "nil")"
        )

        // If already loaded with full content, just show it
        if let parent = effectiveParentPost, parent.content != "..." {
            print("📱 Parent post already loaded with full content, using cached version")
            print("📱 Parent post: username=\(parent.authorUsername), id=\(parent.id)")
            return
        }

        // Otherwise try to fetch it based on platform
        if entry.post.platform == .bluesky {
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
        } else if entry.post.platform == .mastodon {
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

    // Handle action button taps
    private func handleAction(_ action: PostAction) {
        switch action {
        case .reply:
            showDetailView = true
        case .repost:
            Task {
                do {
                    _ = try await serviceManager.repostPost(entry.post)
                } catch {
                    print("Error reposting: \(error)")
                }
            }
        case .like:
            Task {
                do {
                    _ = try await serviceManager.likePost(entry.post)
                } catch {
                    print("Error liking: \(error)")
                }
            }
        case .share:
            // Share the post URL
            let url = URL(string: entry.post.originalURL) ?? URL(string: "https://example.com")!

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
    PostCardView(
        entry: TimelineEntry(
            id: "sample-0",
            kind: .normal,
            post: Post.samplePosts[0],
            createdAt: Date()
        )
    )
    .environmentObject(SocialServiceManager())
    .preferredColorScheme(.dark)
}

#Preview("Reply Post") {
    PostCardView(
        entry: TimelineEntry(
            id: "reply-sample-1",
            kind: .reply(parentId: Post.samplePosts[1].inReplyToID),
            post: Post.samplePosts[1],
            createdAt: Date()
        )
    )
    .environmentObject(SocialServiceManager())
    .preferredColorScheme(.dark)
}

#Preview("Boosted Post") {
    PostCardView(
        entry: TimelineEntry(
            id: "boost-sample-2",
            kind: .boost(boostedBy: Post.samplePosts[2].boostedBy ?? "someone"),
            post: Post.samplePosts[2],
            createdAt: Date()
        )
    )
    .environmentObject(SocialServiceManager())
    .preferredColorScheme(.dark)
}
