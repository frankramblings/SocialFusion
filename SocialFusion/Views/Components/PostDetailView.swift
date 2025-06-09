import Foundation
import SwiftUI
import UIKit

/// A navigation-optimized view that displays the details of a post (not modal)
struct PostDetailNavigationView: View {
    @ObservedObject var viewModel: PostViewModel
    let focusReplyComposer: Bool
    @EnvironmentObject var serviceManager: SocialServiceManager
    @State private var replyText: String = ""
    @State private var isReplying: Bool = false
    @State private var error: AppError? = nil
    @Environment(\.dismiss) private var dismiss

    // Date formatter for detailed timestamp
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // Platform color for reply context
    private var platformColor: Color {
        let displayPost = viewModel.post.originalPost ?? viewModel.post
        switch displayPost.platform {
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
        }
    }

    // Check if reply can be sent
    private var canSendReply: Bool {
        !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && replyText.count <= 500
    }

    init(viewModel: PostViewModel, focusReplyComposer: Bool) {
        self.viewModel = viewModel
        self.focusReplyComposer = focusReplyComposer

        // Auto-open reply composer if requested
        if focusReplyComposer {
            _isReplying = State(initialValue: true)
        }
    }

    var body: some View {
        let displayPost = viewModel.post.originalPost ?? viewModel.post
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Author info
                HStack(spacing: 12) {
                    PostAuthorImageView(
                        authorProfilePictureURL: displayPost.authorProfilePictureURL,
                        platform: displayPost.platform
                    )
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayPost.authorName)
                            .font(.headline)
                            .fontWeight(.semibold)

                        Text("@\(displayPost.authorUsername)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Time stamp
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(dateFormatter.string(from: displayPost.createdAt))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Platform indicator
                        Image(systemName: displayPost.platform.icon)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Content
                displayPost.contentView(lineLimit: nil, showLinkPreview: true, font: .body)

                // Media attachments
                if !displayPost.attachments.isEmpty {
                    UnifiedMediaGridView(attachments: displayPost.attachments)
                }

                // Action bar
                ObservableActionBar(
                    viewModel: viewModel,
                    onAction: handleAction,
                    onOpenInBrowser: {
                        if let url = URL(string: displayPost.originalURL) {
                            UIApplication.shared.open(url)
                        }
                    },
                    onCopyLink: {
                        UIPasteboard.general.string = displayPost.originalURL
                    },
                    onReport: {
                        // TODO: Implement report functionality
                        print("Report post: \(displayPost.id)")
                    }
                )

                // Reply interface
                if isReplying {
                    VStack(spacing: 16) {
                        // Reply header with platform theming
                        HStack {
                            Rectangle()
                                .fill(platformColor)
                                .frame(width: 3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Replying to @\(displayPost.authorUsername)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(platformColor)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(platformColor.opacity(0.1))
                        )

                        // Text input with platform-themed border and auto-focus
                        VStack(spacing: 12) {
                            // Use FocusableTextEditor for reliable auto-focus
                            FocusableTextEditor(
                                text: $replyText,
                                placeholder: "Reply to \(displayPost.authorName)...",
                                shouldAutoFocus: focusReplyComposer,
                                onFocusChange: { _ in }
                            )
                            .frame(minHeight: 100)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(platformColor.opacity(0.3), lineWidth: 1)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(UIColor.systemBackground))
                                    )
                            )

                            // Reply actions
                            HStack {
                                // Character count
                                let remainingChars = 500 - replyText.count
                                Text("\(remainingChars)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(
                                        remainingChars < 0
                                            ? .red : remainingChars < 50 ? .orange : .secondary
                                    )

                                Spacer()

                                // Cancel button
                                Button("Cancel") {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        isReplying = false
                                        replyText = ""
                                    }
                                }
                                .foregroundColor(.secondary)

                                // Send button
                                Button("Reply") {
                                    sendReply()
                                }
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(
                                            canSendReply
                                                ? platformColor : Color.gray.opacity(0.5)
                                        )
                                )
                                .disabled(!canSendReply)
                                .animation(.easeInOut(duration: 0.2), value: canSendReply)
                            }
                        }
                        .padding(.top, 16)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color(.systemBackground))
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .handleAppErrors(error: $viewModel.error)
        .onAppear {
            // Auto-focus reply if requested and not already replying
            if focusReplyComposer && !isReplying {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        isReplying = true
                    }
                }
            }
        }
    }

    private func handleAction(_ action: PostAction) {
        switch action {
        case .like:
            Task { await viewModel.like() }
        case .repost:
            Task { await viewModel.repost() }
        case .reply:
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                isReplying = true
            }
        case .share:
            viewModel.share()
        }
    }

    private func sendReply() {
        Task {
            do {
                let _ = try await serviceManager.replyToPost(viewModel.post, content: replyText)
                // Reset state after successful reply with animation
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isReplying = false
                        replyText = ""
                    }
                }
            } catch let replyError {
                print("Error sending reply: \(replyError)")
                await MainActor.run {
                    // You could add error handling UI here if needed
                    print("Reply failed: \(replyError.localizedDescription)")
                }
            }
        }
    }
}

struct PostDetailNavigationView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PostDetailNavigationView(
                viewModel: PostViewModel(
                    post: Post.samplePosts[0], serviceManager: SocialServiceManager()),
                focusReplyComposer: false
            )
            .environmentObject(SocialServiceManager())
        }
    }
}
