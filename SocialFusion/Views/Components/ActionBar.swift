import SwiftUI

/// ActionBar component for social media post interactions
struct ActionBar: View {
    var isLiked: Bool = false
    var isReposted: Bool = false
    var likeCount: Int = 0
    var repostCount: Int = 0
    var replyCount: Int = 0
    var onAction: (PostAction) -> Void

    var body: some View {
        HStack(spacing: 24) {
            // Reply button
            Button {
                onAction(.reply)
            } label: {
                Label {
                    if replyCount > 0 {
                        Text("\(replyCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "bubble.left")
                        .foregroundColor(.secondary)
                }
            }

            // Repost button
            Button {
                onAction(.repost)
            } label: {
                Label {
                    if repostCount > 0 {
                        Text("\(repostCount)")
                            .font(.caption)
                            .foregroundColor(isReposted ? .green : .secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.2.squarepath")
                        .foregroundColor(isReposted ? .green : .secondary)
                }
            }

            // Like button
            Button {
                onAction(.like)
            } label: {
                Label {
                    if likeCount > 0 {
                        Text("\(likeCount)")
                            .font(.caption)
                            .foregroundColor(isLiked ? .red : .secondary)
                    }
                } icon: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .foregroundColor(isLiked ? .red : .secondary)
                }
            }

            // Share button
            Button {
                onAction(.share)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .font(.system(size: 16))
        .padding(.vertical, 8)
    }
}

// Convenience initializer for ActionBar that takes a Post
extension ActionBar {
    init(post: Post, onAction: @escaping (PostAction) -> Void) {
        self.isLiked = post.isLiked
        self.isReposted = post.isReposted
        self.likeCount = post.likeCount
        self.repostCount = post.repostCount
        self.replyCount = 0  // Post doesn't include replyCount
        self.onAction = onAction
    }
}

struct ActionBar_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ActionBar(
                isLiked: false,
                isReposted: false,
                likeCount: 5,
                repostCount: 2,
                replyCount: 1,
                onAction: { _ in }
            )
            .previewDisplayName("Normal State")

            ActionBar(
                isLiked: true,
                isReposted: true,
                likeCount: 5,
                repostCount: 2,
                replyCount: 1,
                onAction: { _ in }
            )
            .previewDisplayName("Active State")

            ActionBar(
                onAction: { _ in }
            )
            .previewDisplayName("No Counts")
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
