import SwiftUI

/// ActionBar component for social media post interactions
struct ActionBar: View {
    let isLiked: Bool
    let isReposted: Bool
    let likeCount: Int
    let repostCount: Int
    let replyCount: Int
    let onAction: (PostAction) -> Void

    // Consistent spacing between action buttons
    private let buttonSpacing: CGFloat = 32
    // Icon size for better visibility
    private let iconSize: CGFloat = 18

    var body: some View {
        HStack(spacing: buttonSpacing) {
            // Reply button
            Button {
                onAction(.reply)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: iconSize))
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Reply")
                    if replyCount > 0 {
                        Text("\(replyCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("0")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Reply")

            // Repost button
            Button {
                onAction(.repost)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.system(size: iconSize))
                        .foregroundColor(isReposted ? .green : .secondary)
                        .accessibilityLabel(isReposted ? "Undo Repost" : "Repost")
                    if repostCount > 0 {
                        Text("\(repostCount)")
                            .font(.caption)
                            .foregroundColor(isReposted ? .green : .secondary)
                    } else {
                        Text("0")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(isReposted ? "Undo Repost" : "Repost")

            // Like button
            Button {
                onAction(.like)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: iconSize))
                        .foregroundColor(isLiked ? .red : .secondary)
                        .accessibilityLabel(isLiked ? "Unlike" : "Like")
                    if likeCount > 0 {
                        Text("\(likeCount)")
                            .font(.caption)
                            .foregroundColor(isLiked ? .red : .secondary)
                    } else {
                        Text("0")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(isLiked ? "Unlike" : "Like")

            Spacer()

            // Share button
            Button {
                onAction(.share)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: iconSize))
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Share")
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Share")
        }
        .padding(.vertical, 4)
    }
}

// Convenience initializer for ActionBar that takes a Post
extension ActionBar {
    init(post: Post, onAction: @escaping (PostAction) -> Void) {
        self.isLiked = post.isLiked
        self.isReposted = post.isReposted
        self.likeCount = post.likeCount
        self.repostCount = post.repostCount
        self.replyCount = 0  // Post doesn't include replyCount yet
        self.onAction = onAction
    }

    // Convenience initializer for ActionBar that takes a PostViewModel
    init(viewModel: PostViewModel, onAction: @escaping (PostAction) -> Void) {
        self.isLiked = viewModel.isLiked
        self.isReposted = viewModel.isReposted
        self.likeCount = viewModel.likeCount
        self.repostCount = viewModel.repostCount
        self.replyCount = 0
        self.onAction = onAction
    }
}

/// ActionBarViewModel for observing PostViewModel state changes
struct ObservableActionBar: View {
    @ObservedObject var viewModel: PostViewModel
    let onAction: (PostAction) -> Void

    var body: some View {
        ActionBar(
            isLiked: viewModel.isLiked,
            isReposted: viewModel.isReposted,
            likeCount: viewModel.likeCount,
            repostCount: viewModel.repostCount,
            replyCount: 0,
            onAction: onAction
        )
    }
}

#Preview("Normal State") {
    ActionBar(
        isLiked: false,
        isReposted: false,
        likeCount: 5,
        repostCount: 2,
        replyCount: 1,
        onAction: { _ in }
    )
    .padding()
    .background(Color.black)
}

#Preview("Active State") {
    ActionBar(
        isLiked: true,
        isReposted: true,
        likeCount: 5,
        repostCount: 2,
        replyCount: 1,
        onAction: { _ in }
    )
    .padding()
    .background(Color.black)
}

#Preview("No Counts") {
    ActionBar(
        isLiked: false,
        isReposted: false,
        likeCount: 0,
        repostCount: 0,
        replyCount: 0,
        onAction: { _ in }
    )
    .padding()
    .background(Color.black)
}
