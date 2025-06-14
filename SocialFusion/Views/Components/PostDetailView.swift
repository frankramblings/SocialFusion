import Foundation
import SwiftUI

/// A view that displays the details of a post
struct PostDetailModalView: View {
    @ObservedObject var viewModel: PostViewModel
    @Binding var focusReplyComposer: Bool
    @EnvironmentObject var serviceManager: SocialServiceManager
    @State private var replyText: String = ""
    @State private var isReplying: Bool = false
    @State private var error: AppError? = nil

    // Date formatter for detailed timestamp
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        let displayPost = viewModel.post.originalPost ?? viewModel.post
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                if !displayPost.content.isEmpty {
                    displayPost.contentView()
                }

                // Media attachments
                if !displayPost.attachments.isEmpty {
                    UnifiedMediaGridView(attachments: displayPost.attachments)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                }

                // Post metadata
                VStack(alignment: .leading, spacing: 8) {
                    // Timestamp
                    Text(
                        dateFormatter.string(
                            from: viewModel.post.originalPost != nil
                                ? viewModel.post.createdAt : displayPost.createdAt)
                    )
                    .font(.footnote)
                    .foregroundColor(.secondary)

                    // Stats
                    HStack(spacing: 12) {
                        if viewModel.repostCount > 0 {
                            Label(
                                "\(viewModel.repostCount) Reposts",
                                systemImage: "arrow.2.squarepath")
                        }

                        if viewModel.likeCount > 0 {
                            Label("\(viewModel.likeCount) Likes", systemImage: "heart")
                        }
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)

                Divider()

                // Action bar
                ActionBar(
                    isLiked: viewModel.isLiked,
                    isReposted: viewModel.isReposted,
                    likeCount: viewModel.likeCount,
                    repostCount: viewModel.repostCount,
                    replyCount: 0,
                    onAction: handleAction
                )

                // Reply section (appears when reply button is tapped)
                if isReplying {
                    Divider()

                    VStack(alignment: .leading) {
                        Text("Reply to \(displayPost.authorName)")
                            .font(.headline)
                            .padding(.bottom, 8)

                        TextEditor(text: $replyText)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .onAppear {
                                if focusReplyComposer {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        UIApplication.shared.sendAction(
                                            #selector(UIResponder.becomeFirstResponder), to: nil,
                                            from: nil, for: nil)
                                        focusReplyComposer = false
                                    }
                                }
                            }

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
        .background(Color(.systemBackground))
        .handleAppErrors(error: $viewModel.error)
    }

    private func handleAction(_ action: PostAction) {
        switch action {
        case .like:
            Task { await viewModel.like() }
        case .repost:
            Task { await viewModel.repost() }
        case .reply:
            isReplying = true
        case .share:
            viewModel.share()
        }
    }

    private func sendReply() {
        Task {
            do {
                let _ = try await serviceManager.replyToPost(viewModel.post, content: replyText)
                // Reset state after successful reply
                isReplying = false
                replyText = ""
            } catch {
                print("Error sending reply: \(error)")
            }
        }
    }
}

struct PostDetailModalView_Previews: PreviewProvider {
    static var previews: some View {
        PostDetailModalView(
            viewModel: PostViewModel(
                post: Post.samplePosts[0], serviceManager: SocialServiceManager()),
            focusReplyComposer: .constant(false)
        )
        .environmentObject(SocialServiceManager())
    }
}
