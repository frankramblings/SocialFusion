import SwiftUI

/// Post action types
enum PostAction {
    case reply
    case repost
    case like
    case share
}

/// A simplified version of PostCardView
struct PostCardView: View {
    let post: Post
    @State private var showDetailView = false
    @EnvironmentObject var serviceManager: SocialServiceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Post header
            HStack {
                // Avatar
                AsyncImage(url: URL(string: post.authorProfilePictureURL)) { phase in
                    if let image = phase.image {
                        image.resizable()
                    } else {
                        Circle().fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                // Author info
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(.subheadline.weight(.semibold))
                    Text(post.authorUsername)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Post time
                Text(post.timestamp.relativeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Post content
            post.contentView(lineLimit: 3)
                .font(.body)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Action buttons
            HStack(spacing: 32) {
                Button(action: { showDetailView = true }) {
                    Label("\(post.replyCount)", systemImage: "bubble.left")
                }

                Button(action: {}) {
                    Label("\(post.repostCount)", systemImage: "arrow.2.squarepath")
                }

                Button(action: {}) {
                    Label("\(post.likeCount)", systemImage: "heart")
                }

                Button(action: {}) {
                    Label("", systemImage: "square.and.arrow.up")
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .labelStyle(.iconOnly)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .onTapGesture {
            showDetailView = true
        }
        .sheet(isPresented: $showDetailView) {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading) {
                        // Simplified detail view
                        Text("Post Detail")
                            .font(.headline)

                        post.contentView()
                            .font(.body)
                    }
                    .padding()
                }
                .navigationTitle("Post")
                .navigationBarItems(
                    trailing: Button("Close") {
                        showDetailView = false
                    })
            }
        }
    }
}
