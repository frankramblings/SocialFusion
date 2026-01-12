import SwiftUI

// MARK: - Main Share Image View

/// Root view for rendering a share image
struct ShareImageRootView: View {
    let document: ShareImageDocument
    let designWidth: CGFloat = 390  // Fixed design width in points
    let targetPixelWidth: CGFloat

    init(document: ShareImageDocument, targetPixelWidth: CGFloat = 1080) {
        self.document = document
        self.targetPixelWidth = targetPixelWidth
    }

    var scale: CGFloat {
        targetPixelWidth / designWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Post content (no nested card - flat on surface)
            if document.includePostDetails {
                SharePostContentView(
                    post: document.selectedPost,
                    showBoostBanner: document.includePostDetails,
                    showDetailedTimestamp: document.ancestorChain.isEmpty
                        && document.replySubtree.isEmpty,
                    scale: scale
                )
                .padding(.horizontal, 12 * scale)
                .padding(.top, 12 * scale)
                .padding(.bottom, document.allComments.isEmpty ? 12 * scale : 8 * scale)
            }

            // Subtle divider before replies (if any)
            if !document.allComments.isEmpty {
                Divider()
                    .background(Color.secondary.opacity(0.2))
                    .padding(.horizontal, 12 * scale)
                    .padding(.vertical, 6 * scale)
            }

            // Replies Section (thread rows, same surface)
            if !document.allComments.isEmpty {
                ShareRepliesSectionView(
                    comments: document.allComments,
                    scale: scale
                )
                .padding(.horizontal, 12 * scale)
                .padding(.bottom, document.showWatermark ? 8 * scale : 12 * scale)
            }

            // Watermark
            if document.showWatermark {
                HStack {
                    Spacer()
                    ShareWatermarkView()
                        .padding(.trailing, 12 * scale)
                        .padding(.bottom, 12 * scale)
                }
            }
        }
        .frame(width: designWidth * scale)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8 * scale, x: 0, y: 2 * scale)
    }
}

// MARK: - Post Content View

/// Post content rendered flat on surface (no nested card)
struct SharePostContentView: View {
    let post: PostRenderable
    let showBoostBanner: Bool
    let showDetailedTimestamp: Bool
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            // Boost banner
            if showBoostBanner, let boostData = post.boostBannerData {
                HStack(spacing: 4 * scale) {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Boosted by \(boostData.boosterHandle)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 4 * scale)
            }

            // Author info
            HStack(spacing: 8 * scale) {
                // Avatar (synchronous, never fails)
                ShareSynchronousAvatarView(
                    url: post.authorAvatarURL,
                    size: 40,
                    scale: scale
                )

                VStack(alignment: .leading, spacing: 2 * scale) {
                    Text(post.authorDisplayName)
                        .font(.system(size: 15 * scale, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 4 * scale) {
                        Text("@\(post.authorHandle)")
                            .font(.system(size: 13 * scale))
                            .foregroundColor(.secondary)

                        Text("•")
                            .font(.system(size: 13 * scale))
                            .foregroundColor(.secondary)

                        Text(post.timestampString)
                            .font(.system(size: 13 * scale))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Network label
                Text(post.networkLabel)
                    .font(.system(size: 11 * scale, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8 * scale)
                    .padding(.vertical, 4 * scale)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Content
            Text(post.content)
                .font(.system(size: 15 * scale))
                .foregroundColor(.primary)
                .lineSpacing(1.5 * scale)
                .padding(.top, 2 * scale)

            // Media thumbnails
            if !post.mediaThumbnails.isEmpty {
                ShareMediaStripView(thumbnails: post.mediaThumbnails, scale: scale)
                    .padding(.top, 6 * scale)
            }

            // Link preview (lighter embed)
            if let linkPreview = post.linkPreviewData {
                ShareLinkPreviewView(data: linkPreview, scale: scale)
                    .padding(.top, 6 * scale)
            }

            // Quote post (lighter embed)
            if let quotePost = post.quotePostData {
                ShareQuotePostView(data: quotePost, scale: scale)
                    .padding(.top, 6 * scale)
            }

            // Stats
            if !post.statsString.isEmpty {
                Text(post.statsString)
                    .font(.system(size: 12 * scale))
                    .foregroundColor(.secondary)
                    .padding(.top, 6 * scale)
            }

            // Detailed timestamp for "Just this" mode
            if showDetailedTimestamp, let detailedTimestamp = post.detailedTimestampString {
                Text(detailedTimestamp)
                    .font(.system(size: 12 * scale))
                    .foregroundColor(.secondary)
                    .padding(.top, 4 * scale)
            }
        }
    }
}

// MARK: - Replies Section View

/// Replies rendered as thread rows (Apollo-style)
struct ShareRepliesSectionView: View {
    let comments: [CommentRenderable]
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            ForEach(comments) { comment in
                ShareCommentView(comment: comment, scale: scale)
            }
        }
    }
}

// MARK: - Comment View

struct ShareCommentView: View {
    let comment: CommentRenderable
    let scale: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Thread bar (Apollo-style vertical spine)
            if comment.depth > 0 {
                RoundedRectangle(cornerRadius: 1 * scale)
                    .fill(
                        comment.isSelected
                            ? Color.secondary.opacity(0.4)  // Slightly darker for selected
                            : Color.secondary.opacity(0.25)  // Neutral thread bar
                    )
                    .frame(width: 2 * scale)
                    .padding(.trailing, 12 * scale)
            }

            VStack(alignment: .leading, spacing: 4 * scale) {
                // "Replying to..." label (subtle, compact)
                if comment.depth > 0, let parentName = comment.parentAuthorDisplayName {
                    Text("Replying to \(parentName)")
                        .font(.system(size: 10 * scale))
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.bottom, 1 * scale)
                }

                // Author and timestamp (compact row)
                HStack(spacing: 5 * scale) {
                    // Avatar (synchronous, never fails)
                    ShareSynchronousAvatarView(
                        url: comment.authorAvatarURL,
                        size: 20,
                        scale: scale
                    )

                    Text(comment.authorDisplayName)
                        .font(.system(size: 13 * scale, weight: .medium))
                        .foregroundColor(.primary)

                    Text("@\(comment.authorHandle)")
                        .font(.system(size: 11 * scale))
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.system(size: 11 * scale))
                        .foregroundColor(.secondary)

                    Text(comment.timestampString)
                        .font(.system(size: 11 * scale))
                        .foregroundColor(.secondary)

                    if comment.isSelected {
                        Text("Selected")
                            .font(.system(size: 9 * scale, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.7))
                            .padding(.leading, 4 * scale)
                    }

                    Spacer()
                }

                // Content (tighter spacing for density)
                Text(comment.content)
                    .font(.system(size: 13 * scale))
                    .foregroundColor(.primary)
                    .lineSpacing(1.5 * scale)
            }

            Spacer()
        }
        // Indentation for thread structure
        .padding(.leading, comment.depth > 0 ? 12 * scale : 0)
        .padding(.vertical, 5 * scale)
        // Very subtle background wash for selected only (no card feel)
        .background(
            comment.isSelected
                ? Color.secondary.opacity(0.04)  // Minimal wash
                : Color.clear
        )
    }
}

// MARK: - Media Strip View

struct ShareMediaStripView: View {
    let thumbnails: [PostRenderable.MediaThumbnail]
    let scale: CGFloat

    var body: some View {
        // For single images, display full width with proper aspect ratio (like in feed)
        if thumbnails.count == 1 {
            ShareSingleImageView(thumbnail: thumbnails[0], scale: scale)
        } else {
            // For multiple images, use grid layout
            let gridColumns = min(thumbnails.count, 3)
            let itemSize =
                (390 - 32 - (CGFloat(gridColumns - 1) * 4)) / CGFloat(gridColumns) * scale

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 4 * scale), count: gridColumns),
                spacing: 4 * scale
            ) {
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, thumbnail in
                    GeometryReader { geometry in
                        ShareSynchronousImageView(url: thumbnail.url, scale: scale) {
                            AnyView(
                                RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                                    .fill(Color.secondary.opacity(0.2))
                                    .overlay(
                                        Text(
                                            thumbnail.placeholder.isEmpty
                                                ? "📷" : thumbnail.placeholder
                                        )
                                        .font(.system(size: 24 * scale))
                                        .foregroundColor(.secondary)
                                    )
                            )
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
                    }
                    .aspectRatio(1.0, contentMode: .fit)
                }
            }
        }
    }
}

// MARK: - Single Image View (Full Width)

/// Single image view that displays full width with proper aspect ratio (like in feed)
struct ShareSingleImageView: View {
    let thumbnail: PostRenderable.MediaThumbnail
    let scale: CGFloat

    // Calculate aspect ratio from cached image if available
    private var aspectRatio: CGFloat? {
        guard let url = thumbnail.url,
            let image = ImageCache.shared.getCachedImage(for: url)
        else {
            return nil
        }
        let size = image.size
        guard size.height > 0 else { return nil }
        return size.width / size.height
    }

    // Use default aspect ratio if image not cached yet (should be rare due to preloading)
    private var effectiveAspectRatio: CGFloat {
        aspectRatio ?? 16.0 / 9.0  // Default to 16:9 if not available
    }

    // Max height to prevent excessive image sizes (scaled appropriately)
    private var maxHeight: CGFloat {
        600 * scale  // Reasonable max height for share images
    }

    var body: some View {
        ShareSynchronousImageView(url: thumbnail.url, scale: scale) {
            AnyView(
                RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay(
                        Text(
                            thumbnail.placeholder.isEmpty ? "📷" : thumbnail.placeholder
                        )
                        .font(.system(size: 24 * scale))
                        .foregroundColor(.secondary)
                    )
            )
        }
        .aspectRatio(effectiveAspectRatio, contentMode: .fit)  // Apply aspect ratio and fit mode
        .frame(maxWidth: .infinity)  // Full width
        .frame(maxHeight: maxHeight)  // Cap the height
        .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
    }
}

// MARK: - Link Preview View

struct ShareLinkPreviewView: View {
    let data: PostRenderable.LinkPreviewData
    let scale: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 12 * scale) {
            // Thumbnail (synchronous, never fails, preserves aspect ratio)
            if let thumbnailURL = data.thumbnailURL {
                ShareSynchronousImageView(url: thumbnailURL, scale: scale) {
                    AnyView(
                        RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                            .fill(Color.secondary.opacity(0.2))
                    )
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 80 * scale, height: 80 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
            }

            // Text content
            VStack(alignment: .leading, spacing: 4 * scale) {
                Text(data.title)
                    .font(.system(size: 14 * scale, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                if let description = data.description {
                    Text(description)
                        .font(.system(size: 12 * scale))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Text(data.url.host ?? "")
                    .font(.system(size: 11 * scale))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(10 * scale)
        .background(Color.secondary.opacity(0.06))  // Lighter, lower contrast
        .clipShape(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous))  // Smaller radius
    }
}

// MARK: - Quote Post View

struct ShareQuotePostView: View {
    let data: PostRenderable.QuotePostData
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            // Author
            HStack(spacing: 6 * scale) {
                Text(data.authorDisplayName)
                    .font(.system(size: 13 * scale, weight: .semibold))
                    .foregroundColor(.primary)

                Text("@\(data.authorHandle)")
                    .font(.system(size: 11 * scale))
                    .foregroundColor(.secondary)
            }

            // Content
            Text(data.content)
                .font(.system(size: 13 * scale))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)  // Allow vertical expansion, respect horizontal constraints

            // Media
            if !data.mediaThumbnails.isEmpty {
                ShareMediaStripView(thumbnails: data.mediaThumbnails, scale: scale)
                    .padding(.top, 6 * scale)
            }
        }
        .padding(10 * scale)
        .background(Color.secondary.opacity(0.06))  // Lighter, lower contrast
        .clipShape(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous))  // Smaller radius
    }
}

// MARK: - Watermark View

struct ShareWatermarkView: View {
    var body: some View {
        Text("via SocialFusion")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .clipShape(Capsule())
    }
}

// MARK: - Avatar Placeholder

private func avatarPlaceholder(scale: CGFloat, size: CGFloat = 40) -> some View {
    Circle()
        .fill(
            LinearGradient(
                colors: [
                    Color.secondary.opacity(0.3),
                    Color.secondary.opacity(0.2),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .frame(width: size * scale, height: size * scale)
        .overlay(
            Image(systemName: "person.fill")
                .font(.system(size: (size * 0.5) * scale))
                .foregroundColor(.secondary.opacity(0.6))
        )
}
