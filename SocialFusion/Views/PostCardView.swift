import Foundation
import LinkPresentation  // For link previews
import SocialFusion.ViewModels.PostViewModel
import SocialFusion.Views.Components.QuotePostView
import SocialFusion.Views.Components.UnifiedMediaGridView
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
    @State private var bannerWasTapped = false
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @EnvironmentObject private var account: SocialAccount?
    @Environment(\.colorScheme) private var colorScheme
    let post: Post
    let timelineKind: TimelineEntryKind?
    @State private var shouldShowParentPost = false

    // Convenience initializer for direct Post usage (existing behavior)
    init(viewModel: PostViewModel, post: Post, account: SocialAccount?) {
        self.viewModel = viewModel
        self.post = post
        self.account = account
        self.timelineKind = nil
    }

    // New initializer for TimelineEntry usage
    init(entry: TimelineEntry) {
        self.post = entry.post
        self.timelineKind = entry.kind
        self.account = nil  // Will be resolved from service manager
        self.viewModel = PostViewModel(
            post: entry.post, serviceManager: SocialServiceManager.shared)
    }

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
        let displayPost = viewModel.post.originalPost ?? viewModel.post
        VStack(alignment: .leading, spacing: 8) {
            // Author info
            HStack(alignment: .center) {
                // Avatar
                AsyncImage(url: URL(string: displayPost.authorProfilePictureURL)) { phase in
                    if let image = phase.image {
                        image.resizable()
                    } else if phase.error != nil {
                        Color.gray.opacity(0.3)
                    } else {
                        Color.gray.opacity(0.1)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayPost.authorName)
                        .font(.headline)

                    Text("@\(displayPost.authorUsername)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Platform indicator
                PlatformDot(platform: displayPost.platform)
            }

            // Post content
            Text(displayPost.content)
                .font(.body)
                .padding(.vertical, 4)

            // Render quoted post if available
            if let quotedPostViewModel = viewModel.quotedPostViewModel {
                QuotePostView(viewModel: quotedPostViewModel)
                    .padding(.vertical, 4)
            }

            // Media attachments
            if !displayPost.attachments.isEmpty {
                UnifiedMediaGridView(attachments: displayPost.attachments)
                    .padding(.vertical, 4)
            }

            // Action buttons
            HStack(spacing: 24) {
                Button(action: { /* reply */  }) {
                    Image(systemName: "bubble.left")
                }.disabled(account == nil)
                Button(action: { /* boost/repost */  }) {
                    Image(systemName: "arrow.2.squarepath")
                }.disabled(account == nil)
                Button(action: { /* like */  }) {
                    Image(systemName: "heart")
                }.disabled(account == nil)
                Button(action: { /* share */  }) {
                    Image(systemName: "square.and.arrow.up")
                }
                Spacer()
                // Only show edit/delete for user's own posts
                if let account = account, account.username == displayPost.authorUsername {
                    Button(action: { /* edit */  }) {
                        Image(systemName: "pencil")
                    }
                    Button(action: { /* delete */  }) {
                        Image(systemName: "trash")
                    }
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.top, 4)
            Divider()
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
        .contentShape(Rectangle())
        .onTapGesture {
            if !bannerWasTapped {
                showDetailView = true
            }
            bannerWasTapped = false
        }
        .sheet(isPresented: $showDetailView, onDismiss: { shouldFocusReplyComposer = false }) {
            NavigationView {
                PostDetailView(viewModel: viewModel, focusReplyComposer: $shouldFocusReplyComposer)
            }
        }
        .onAppear {
            print("[PostCardView] onAppear for postId=\(viewModel.post.id)")
        }
        .onDisappear {
            print("[PostCardView] onDisappear for postId=\(post.id)")
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
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading parent post...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
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

// If the above import does not work, copy the PostAttachmentView definition here:
private struct PostAttachmentView: View {
    let attachment: Post.Attachment

    var body: some View {
        AsyncImage(url: URL(string: attachment.url)) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .cornerRadius(14)
                    .clipped()
            } else if phase.error != nil {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .cornerRadius(14)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    )
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .cornerRadius(14)
                    .overlay(
                        ProgressView()
                    )
            }
        }
    }
}

// MARK: - Timeline Banner
struct TimelineBanner: View {
    enum BannerType {
        case reply(username: String, network: SocialPlatform, isExpanded: Bool, onTap: () -> Void)
        case repost(username: String, network: SocialPlatform)
    }

    let type: BannerType
    @Environment(\.colorScheme) private var colorScheme

    // Helper function to return appropriate glow color based on color scheme
    private func adaptiveGlowColor(opacity: Double) -> Color {
        colorScheme == .dark ? Color.white.opacity(opacity) : Color.black.opacity(opacity * 0.7)
    }

    var body: some View {
        switch type {
        case .reply(let username, let network, let isExpanded, let onTap):
            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.up.left")
                    .font(.caption)
                    .foregroundColor(network.secondaryColor)
                Text("Replying to @\(username)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.adaptiveElementBackground(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.adaptiveElementBorder(for: colorScheme), lineWidth: 0.5)
            )
            .shadow(color: adaptiveGlowColor(opacity: 0.03), radius: 0.5, x: 0, y: 0)
            .shadow(color: adaptiveGlowColor(opacity: 0.02), radius: 1, x: 0, y: 0)
            .shadow(
                color: colorScheme == .dark
                    ? Color.elementShadow : Color.black.opacity(0.05), radius: 1, y: 1
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityLabel("Replying to @\(username)")
        case .repost(let username, let network):
            HStack(spacing: 4) {
                Image(systemName: "arrow.2.squarepath")
                    .font(.caption)
                    .foregroundColor(network.secondaryColor)
                Text("@\(username) reposted")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.adaptiveElementBackground(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.adaptiveElementBorder(for: colorScheme), lineWidth: 0.5)
            )
            .shadow(color: adaptiveGlowColor(opacity: 0.03), radius: 0.5, x: 0, y: 0)
            .shadow(color: adaptiveGlowColor(opacity: 0.02), radius: 1, x: 0, y: 0)
            .shadow(
                color: colorScheme == .dark
                    ? Color.elementShadow : Color.black.opacity(0.05), radius: 1, y: 1)
        }
    }
}

// Helper for network secondary color
extension SocialPlatform {
    var secondaryColor: Color {
        switch self {
        case .bluesky:
            return Color(red: 0, green: 122 / 255, blue: 255 / 255)
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)
        }
    }
}

// MARK: - Preview
#Preview("Standard Post") {
    PostCardView(
        viewModel: PostViewModel(post: Post.samplePosts[0], serviceManager: SocialServiceManager()),
        post: Post.samplePosts[0],
        account: SocialAccount(
            id: "sample-id-1",
            username: "sampleUser",
            displayName: "Sample User",
            serverURL: "https://bsky.social",
            platform: .bluesky
        )
    )
    .environmentObject(SocialServiceManager())
    .preferredColorScheme(.dark)
}

#Preview("Reply Post") {
    PostCardView(
        viewModel: PostViewModel(post: Post.samplePosts[1], serviceManager: SocialServiceManager()),
        post: Post.samplePosts[1],
        account: SocialAccount(
            id: "sample-id-2",
            username: "sampleUser",
            displayName: "Sample User",
            serverURL: "https://bsky.social",
            platform: .bluesky
        )
    )
    .environmentObject(SocialServiceManager())
    .preferredColorScheme(.dark)
}

#Preview("Boosted Post") {
    PostCardView(
        viewModel: PostViewModel(post: Post.samplePosts[2], serviceManager: SocialServiceManager()),
        post: Post.samplePosts[2],
        account: SocialAccount(
            id: "sample-id-3",
            username: "sampleUser",
            displayName: "Sample User",
            serverURL: "https://bsky.social",
            platform: .bluesky
        )
    )
    .environmentObject(SocialServiceManager())
    .preferredColorScheme(.dark)
}
