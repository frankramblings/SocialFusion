// Forward imports
import SwiftUI

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

    // Animation duration for sliding the parent post
    private let animationDuration: Double = 0.35

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

                                if displayPost.platform == .bluesky {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundColor(blueskyBlue)
                                }
                            }
                        }

                        Spacer()

                        // Timestamp with chevron
                        HStack(spacing: 2) {
                            Text(displayPost.createdAt, style: .relative)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Post content
                    if !displayPost.content.isEmpty {
                        Text(displayPost.content)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }

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
                        isLoadingParent = true
                        await fetchParentPost(replyToID: replyToID)
                        isLoadingParent = false
                    }
                }
            }
        }) {
            HStack {
                Image(systemName: "arrow.turn.up.left")
                    .font(.caption)
                    .foregroundColor(blueskyBlue)

                Text("Replying to ")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    + Text(
                        "@\(effectiveParentPost?.authorUsername ?? displayPost.inReplyToID?.components(separatedBy: "/").last ?? "...")"
                    )
                    .font(.footnote)
                    .foregroundColor(blueskyBlue)

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

    // Fetch parent post if not already loaded
    private func fetchParentPost(replyToID: String) async {
        // If already loaded, just show it
        if effectiveParentPost != nil {
            return
        }

        // Otherwise try to fetch it based on platform
        if displayPost.platform == .bluesky {
            do {
                let fetchedParent = try await serviceManager.fetchBlueskyPostByID(replyToID)
                await MainActor.run {
                    // Use our @State property to store the parent post
                    parentPost = fetchedParent
                }
            } catch {
                print("Error fetching parent post: \(error)")
            }
        } else if displayPost.platform == .mastodon {
            // Implement Mastodon parent post fetching if needed
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
