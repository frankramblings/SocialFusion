import SwiftUI

enum ActionBarAction: CaseIterable {
    case reply
    case repost
    case like
    case share

    func iconName(for post: Post) -> String {
        switch self {
        case .reply:
            return "bubble.left"
        case .repost:
            return post.isReposted ? "arrow.2.squarepath.fill" : "arrow.2.squarepath"
        case .like:
            return post.isLiked ? "heart.fill" : "heart"
        case .share:
            return "square.and.arrow.up"
        }
    }

    func color(for post: Post) -> Color {
        switch self {
        case .reply:
            return .secondary
        case .repost:
            return post.isReposted ? .green : .secondary
        case .like:
            return post.isLiked ? .red : .secondary
        case .share:
            return .secondary
        }
    }

    func count(for post: Post) -> Int {
        switch self {
        case .reply:
            return post.replyCount  // Now we have reply counts!
        case .repost:
            return post.repostCount
        case .like:
            return post.likeCount
        case .share:
            return 0
        }
    }

    func showCount(for post: Post) -> Bool {
        switch self {
        case .reply:
            return post.replyCount > 0  // Show reply count when available
        case .repost:
            return true
        case .like:
            return true
        case .share:
            return false
        }
    }
}

/// Standard action bar (reply / repost / like / share) used in timeline & detail views.
struct ActionBar: View {
    let post: Post
    var onAction: (ActionBarAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ActionBarAction.allCases, id: \.self) { action in
                Spacer()
                Button(action: {
                    onAction(action)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: action.iconName(for: post))
                            .font(.caption)
                            .foregroundColor(action.color(for: post))

                        if action.showCount(for: post) {
                            Text(action.count(for: post) > 0 ? "\(action.count(for: post))" : "")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                Spacer()
            }
        }
        .padding(.top, 4)
    }
}

// Add a mapping extension to convert between action types
extension ActionBar {
    // Convenience initializer to bridge from PostAction to ActionBarAction
    init(post: Post, onAction: @escaping (PostAction) -> Void) {
        self.post = post
        self.onAction = { actionBarAction in
            // Map ActionBarAction to PostAction
            switch actionBarAction {
            case .reply:
                onAction(.reply)
            case .repost:
                onAction(.repost)
            case .like:
                onAction(.like)
            case .share:
                onAction(.share)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ActionBar(post: Post.samplePosts[0]) { action in
            print("Action: \(action)")
        }

        ActionBar(post: Post.samplePosts[1]) { action in
            print("Action: \(action)")
        }
    }
    .padding()
}
