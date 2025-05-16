import SwiftUI

/// A view that displays the details of a post
struct PostDetailView: View {
    let post: Post
    @EnvironmentObject var serviceManager: SocialServiceManager
    @State private var replyText: String = ""
    @State private var isReplying: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Author info
                HStack(alignment: .center) {
                    // Avatar
                    AsyncImage(url: URL(string: post.authorProfilePictureURL)) { phase in
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
                        Text(post.authorName)
                            .font(.headline)

                        Text("@\(post.authorUsername)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Platform indicator
                    PlatformDot(platform: post.platform)
                }

                // Post content
                if !post.content.isEmpty {
                    post.contentView()
                }

                // Media attachments
                if !post.attachments.isEmpty {
                    MediaGridView(
                        attachments: post.attachments.map {
                            MediaAttachment(
                                id: $0.id,
                                url: URL(string: $0.url) ?? URL(string: "https://example.com")!,
                                altText: $0.altText
                            )
                        }
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(8)
                }

                // Post metadata
                VStack(alignment: .leading, spacing: 8) {
                    // Timestamp
                    Text(post.createdAt, style: .date)
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    // Stats
                    HStack(spacing: 12) {
                        if post.repostCount > 0 {
                            Label("\(post.repostCount) Reposts", systemImage: "arrow.2.squarepath")
                        }

                        if post.likeCount > 0 {
                            Label("\(post.likeCount) Likes", systemImage: "heart")
                        }
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)

                Divider()

                // Action bar
                ActionBar(
                    isLiked: post.isLiked,
                    isReposted: post.isReposted,
                    likeCount: post.likeCount,
                    repostCount: post.repostCount,
                    replyCount: 0,  // No replyCount in the model
                    onAction: handleAction
                )

                // Reply section (appears when reply button is tapped)
                if isReplying {
                    Divider()

                    VStack(alignment: .leading) {
                        Text("Reply to \(post.authorName)")
                            .font(.headline)
                            .padding(.bottom, 8)

                        TextEditor(text: $replyText)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)

                        HStack {
                            Spacer()

                            Button("Cancel") {
                                isReplying = false
                                replyText = ""
                            }
                            .padding(.horizontal)

                            Button("Reply") {
                                sendReply()
                            }
                            .padding(.horizontal)
                            .disabled(
                                replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
        }
    }

    private func handleAction(_ action: PostAction) {
        Task {
            switch action {
            case .like:
                do {
                    let _ = try await serviceManager.likePost(post)
                } catch {
                    print("Error liking post: \(error)")
                }
            case .repost:
                do {
                    let _ = try await serviceManager.repostPost(post)
                } catch {
                    print("Error reposting post: \(error)")
                }
            case .reply:
                isReplying = true
            case .share:
                // Show share sheet
                let url = URL(string: post.originalURL) ?? URL(string: "https://example.com")!
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

    private func sendReply() {
        Task {
            do {
                let _ = try await serviceManager.replyToPost(post, content: replyText)
                // Reset state after successful reply
                isReplying = false
                replyText = ""
            } catch {
                print("Error sending reply: \(error)")
            }
        }
    }
}

struct PostDetailView_Previews: PreviewProvider {
    static var previews: some View {
        PostDetailView(post: Post.samplePosts[0])
            .environmentObject(SocialServiceManager())
    }
}
