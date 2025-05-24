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
    @ObservedObject var viewModel: PostViewModel
    @State private var showDetailView = false
    @State private var shouldFocusReplyComposer = false
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

    // Helper to extract Bluesky handle from at:// URI
    private func extractBlueskyHandle(from inReplyToID: String?) -> String? {
        guard let id = inReplyToID, id.hasPrefix("at://") else { return nil }
        let parts = id.split(separator: "/")
        if parts.count > 2 {
            return String(parts[1])
        }
        return nil
    }

    var body: some View {
        TimelineCard {
            VStack(alignment: .leading, spacing: 0) {
                // Boost/Repost banner if applicable
                if case let .boost(boostedBy) = viewModel.kind {
                    BoostBannerView(handle: boostedBy, platform: viewModel.post.platform)
                        .padding(.bottom, 4)
                }

                // Reply banner if applicable
                if case .reply = viewModel.kind {
                    Group {
                        replyBannerView
                            .padding(.bottom, 4)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(
                        .spring(response: animationDuration, dampingFraction: 0.8),
                        value: viewModel.isParentExpanded)
                    // Parent post preview (when expanded) appears above main post content
                    if viewModel.isParentExpanded {
                        if let parent = viewModel.effectiveParentPost, !parent.content.isEmpty {
                            ParentPostPreview(post: parent, onTap: { /* ... */  })
                        } else if viewModel.isLoadingParent {
                            LoadingParentView()
                        }
                        // else: show nothing
                    }
                }

                // Main post content with visual distinction
                VStack(alignment: .leading, spacing: 10) {
                    // For boosts, only show content if originalPost exists and has content or media
                    let displayPost = viewModel.post.originalPost ?? viewModel.post
                    let hasContentOrMedia =
                        !displayPost.content.isEmpty || !displayPost.attachments.isEmpty
                    if case .boost = viewModel.kind, !hasContentOrMedia {
                        // Only show banner and author info, skip content
                        HStack(alignment: .center) {
                            PostAuthorImageView(
                                authorProfilePictureURL: displayPost.authorProfilePictureURL,
                                platform: displayPost.platform,
                                size: 44
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayPost.authorName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                HStack(spacing: 4) {
                                    Text("@\(displayPost.authorUsername)")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            HStack(spacing: 2) {
                                Text(formatRelativeTime(from: displayPost.createdAt))
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        // Post header with author info
                        HStack(alignment: .center) {
                            PostAuthorImageView(
                                authorProfilePictureURL: displayPost.authorProfilePictureURL,
                                platform: displayPost.platform,
                                size: 44
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayPost.authorName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                HStack(spacing: 4) {
                                    Text("@\(displayPost.authorUsername)")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            HStack(spacing: 2) {
                                Text(formatRelativeTime(from: displayPost.createdAt))
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                        // Post content
                        Group {
                            if displayPost.platform == .bluesky {
                                displayPost.blueskyContentView()
                                    .font(.system(size: 16))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 2)
                            } else {
                                displayPost.contentView(lineLimit: nil, showLinkPreview: false)
                                    .font(.system(size: 16))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 2)
                            }
                        }
                        // --- One preview/quote card per post logic ---
                        if let quoteOrPreview = displayPost.firstQuoteOrPreviewCardView {
                            quoteOrPreview
                                .padding(.top, 8)
                        }
                        // Media attachments if any
                        if !displayPost.attachments.isEmpty {
                            UnifiedMediaGridView(
                                attachments: displayPost.attachments, maxHeight: 400
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        // Action bar (use viewModel for actions)
                        ActionBar(
                            isLiked: viewModel.isLiked,
                            isReposted: viewModel.isReposted,
                            likeCount: viewModel.likeCount,
                            repostCount: viewModel.repostCount,
                            replyCount: 0,
                            onAction: handleAction
                        )
                    }
                }
                .padding(.top, viewModel.isParentExpanded ? 8 : 0)
            }
        }
        .onTapGesture {
            showDetailView = true
        }
        .sheet(isPresented: $showDetailView, onDismiss: { shouldFocusReplyComposer = false }) {
            NavigationView {
                PostDetailView(viewModel: viewModel, focusReplyComposer: $shouldFocusReplyComposer)
            }
        }
    }

    // Reply banner at the top of reply posts
    private var replyBannerView: some View {
        Button(action: {
            // Toggle parent post expansion with animation
            withAnimation(.spring(response: animationDuration, dampingFraction: 0.8)) {
                viewModel.isParentExpanded.toggle()
            }

            // If we're expanding and need to fetch the parent
            if viewModel.isParentExpanded && viewModel.effectiveParentPost == nil {
                if let replyToID = viewModel.post.inReplyToID {
                    // No-op: parent hydration is now automatic and handled by the model/service
                }
            } else if viewModel.isParentExpanded && viewModel.effectiveParentPost?.content == "..."
            {
                if let replyToID = viewModel.post.inReplyToID {
                    // No-op: parent hydration is now automatic and handled by the model/service
                }
            }
        }) {
            HStack {
                Image(systemName: "arrow.turn.up.left")
                    .font(.caption)
                    .foregroundColor(
                        viewModel.post.platform == .bluesky ? blueskyBlue : mastodonPurple)

                let replyUsername: String =
                    viewModel.effectiveParentPost?.authorUsername
                    ?? viewModel.post.inReplyToUsername
                    ?? "user"

                (Text("Replying to ")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    + Text("@\(replyUsername)")
                    .font(.footnote)
                    .foregroundColor(
                        viewModel.post.platform == .bluesky ? blueskyBlue : mastodonPurple))
                    .onAppear {
                        print(
                            "[PostCardView] replyUsername: \(replyUsername), parent.authorUsername: \(String(describing: viewModel.effectiveParentPost?.authorUsername))"
                        )
                    }

                Spacer()

                // Chevron indicator with rotation animation
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(viewModel.isParentExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: viewModel.isParentExpanded)
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

    // Helper function to return appropriate glow color based on color scheme
    private func adaptiveGlowColor(opacity: Double) -> Color {
        colorScheme == .dark ? Color.white.opacity(opacity) : Color.black.opacity(opacity * 0.7)  // Slightly reduced opacity for light mode
    }

    // Handle action button taps
    private func handleAction(_ action: PostAction) {
        switch action {
        case .reply:
            shouldFocusReplyComposer = true
            showDetailView = true
        case .repost:
            Task { await viewModel.repost() }
        case .like:
            Task { await viewModel.like() }
        case .share:
            viewModel.share()
        }
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
        viewModel: PostViewModel(post: Post.samplePosts[0], serviceManager: SocialServiceManager())
    )
    .environmentObject(SocialServiceManager())
    .preferredColorScheme(.dark)
}

#Preview("Reply Post") {
    PostCardView(
        viewModel: PostViewModel(post: Post.samplePosts[1], serviceManager: SocialServiceManager())
    )
    .environmentObject(SocialServiceManager())
    .preferredColorScheme(.dark)
}

#Preview("Boosted Post") {
    PostCardView(
        viewModel: PostViewModel(post: Post.samplePosts[2], serviceManager: SocialServiceManager())
    )
    .environmentObject(SocialServiceManager())
    .preferredColorScheme(.dark)
}
