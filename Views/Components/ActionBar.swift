import SwiftUI

private struct ActionButton: View {
    let systemName: String
    let count: Int
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: systemName)
            if count > 0 {
                Text("\(count)")
                    .monospacedDigit()
            }
        }
        .foregroundColor(count == 0 ? .secondary : .accentPurple)
    }
}

/// Post action bar: reply, repost, like, share.
struct ActionBar: View {
    let post: Post
    var body: some View {
        HStack(spacing: 28) {
            ActionButton(systemName: "bubble.left", count: post.replyCount)
            ActionButton(systemName: "arrow.2.squarepath", count: post.repostCount)
            ActionButton(systemName: "heart", count: post.likeCount)
            ShareLink(item: post.url) {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .font(.subheadline)
        .labelStyle(.iconOnly)
        .tint(.accentPurple)
    }
}
