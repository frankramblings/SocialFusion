import Foundation
import SwiftUI
import UIKit

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// A refined post detail view following Mail.app's unified layout styling
struct PostDetailNavigationView: View {
    @ObservedObject var viewModel: PostViewModel
    let focusReplyComposer: Bool
    @EnvironmentObject var serviceManager: SocialServiceManager
    @EnvironmentObject var navigationEnvironment: PostNavigationEnvironment
    @State private var replyText: String = ""
    @State private var isReplying: Bool = false
    @State private var error: AppError? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

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

        GeometryReader { geometry in
            ZStack {
                // Plain dark background like Mail.app
                Color.black
                    .ignoresSafeArea(.all)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Dynamic top spacing to prevent navigation overlap
                        Color.clear
                            .frame(height: max(geometry.safeAreaInsets.top, 20))

                        // All content in one unified flowing section
                        VStack(alignment: .leading, spacing: 0) {
                            // Author section
                            authorSection(for: displayPost)
                                .padding(.horizontal, 16)
                                .padding(.top, 20)
                                .padding(.bottom, 16)

                            // Subtle divider
                            Divider()
                                .background(Color.gray.opacity(0.3))
                                .padding(.horizontal, 16)

                            // Post content
                            postContentSection(for: displayPost)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)

                            // Media attachments
                            if !displayPost.attachments.isEmpty {
                                Divider()
                                    .background(Color.gray.opacity(0.3))
                                    .padding(.horizontal, 16)

                                mediaSection(for: displayPost)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 16)
                            }

                            // Action bar
                            Divider()
                                .background(Color.gray.opacity(0.3))
                                .padding(.horizontal, 16)

                            actionBarSection(for: displayPost)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)

                            // Engagement metadata
                            if viewModel.post.repostCount > 0 || viewModel.post.likeCount > 0 {
                                Divider()
                                    .background(Color.gray.opacity(0.3))
                                    .padding(.horizontal, 16)

                                metadataSection(for: displayPost)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 16)
                            }

                            // Timestamp section
                            Divider()
                                .background(Color.gray.opacity(0.3))
                                .padding(.horizontal, 16)

                            bottomMetadataSection(for: displayPost)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                        }

                        // Reply interface if active
                        if isReplying {
                            replySection(for: displayPost)
                                .padding(.top, 20)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Bottom spacing for proper scroll behavior
                        Color.clear
                            .frame(height: max(100, geometry.safeAreaInsets.bottom + 60))
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .fontWeight(.medium)
                        .frame(width: 32, height: 32)
                        .background(Color.clear)
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button(action: {
                        if let url = URL(string: viewModel.post.originalURL) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Label("Open in Browser", systemImage: "safari")
                    }

                    Button(action: {
                        UIPasteboard.general.string = viewModel.post.originalURL
                    }) {
                        Label("Copy Link", systemImage: "link")
                    }

                    Button(action: {
                        viewModel.share()
                    }) {
                        Label("Share Post", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(
                        role: .destructive,
                        action: {
                            print("Report post: \(viewModel.post.id)")
                        }
                    ) {
                        Label("Report Post", systemImage: "flag")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .handleAppErrors(error: $viewModel.error)
        .onAppear {
            // Auto-focus reply if requested and not already replying
            if focusReplyComposer && !isReplying {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isReplying = true
                    }
                }
            }
        }
    }

    // MARK: - Content Sections

    @ViewBuilder
    private func replySection(for post: Post) -> some View {
        VStack(spacing: 0) {
            // Reply header with clear hierarchy
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(platformColor)
                    .frame(width: 4, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Replying to")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("@\(post.authorUsername)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(platformColor)
                }

                Spacer()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isReplying = false
                        replyText = ""
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            Divider()
                .background(Color.gray.opacity(0.3))
                .padding(.horizontal, 16)

            // Text input with proper styling
            VStack(spacing: 16) {
                FocusableTextEditor(
                    text: $replyText,
                    placeholder: "Reply to \(post.authorName)...",
                    shouldAutoFocus: focusReplyComposer,
                    onFocusChange: { _ in }
                )
                .frame(minHeight: 120)
                .padding(16)
                .background(Color.clear)

                // Action bar with standard button styles
                HStack {
                    let remainingChars = 500 - replyText.count

                    // Character count indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(
                                remainingChars < 0
                                    ? .red : remainingChars < 50 ? .orange : platformColor
                            )
                            .frame(width: 8, height: 8)

                        Text("\(remainingChars)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(remainingChars < 0 ? .red : .secondary)
                    }

                    Spacer()

                    // Standard button grouping
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isReplying = false
                                replyText = ""
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("Reply") {
                            sendReply()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSendReply)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private func bottomMetadataSection(for post: Post) -> some View {
        // Timestamp information with clear hierarchy
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                openPostPermalink(for: post)
            }) {
                Text(dateFormatter.string(from: post.createdAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .underline()
            }
            .buttonStyle(.plain)

            Text("Posted via \(post.platform.rawValue.capitalized)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helper Methods

    private func openPostPermalink(for post: Post) {
        guard let url = URL(string: post.originalURL) else { return }

        // Try to open in the default app first, then fall back to browser
        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                // If opening in the default app fails, try opening in Safari
                UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - Content Components

    @ViewBuilder
    private func authorSection(for post: Post) -> some View {
        HStack(spacing: 12) {
            // Profile image with clean styling
            PostAuthorImageView(
                authorProfilePictureURL: post.authorProfilePictureURL,
                platform: post.platform
            )
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                // Name with clean typography
                Text(post.authorName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("@\(post.authorUsername)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Platform indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(platformColor)
                    .frame(width: 6, height: 6)

                Text(post.platform.rawValue.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(platformColor)
            }
        }
    }

    @ViewBuilder
    private func postContentSection(for post: Post) -> some View {
        post.contentView(
            lineLimit: nil,
            showLinkPreview: true,
            font: .body,
            onQuotePostTap: { quotedPost in
                navigationEnvironment.navigateToPost(quotedPost)
            }
        )
        .font(.body)
        .lineSpacing(4)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func mediaSection(for post: Post) -> some View {
        UnifiedMediaGridView(attachments: post.attachments)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func actionBarSection(for post: Post) -> some View {
        ObservableActionBar(
            viewModel: viewModel,
            onAction: handleAction,
            onOpenInBrowser: {
                if let url = URL(string: post.originalURL) {
                    UIApplication.shared.open(url)
                }
            },
            onCopyLink: {
                UIPasteboard.general.string = post.originalURL
            },
            onReport: {
                print("Report post: \(post.id)")
            }
        )
    }

    @ViewBuilder
    private func metadataSection(for post: Post) -> some View {
        HStack(spacing: 24) {
            if viewModel.post.repostCount > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.post.repostCount)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(viewModel.post.repostCount == 1 ? "Repost" : "Reposts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.post.likeCount > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.post.likeCount)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(viewModel.post.likeCount == 1 ? "Like" : "Likes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Action Handling

    private func handleAction(_ action: PostAction) {
        switch action {
        case .reply:
            withAnimation(.easeInOut(duration: 0.3)) {
                isReplying = true
            }
        case .repost:
            Task {
                await viewModel.repost()
            }
        case .like:
            Task {
                await viewModel.like()
            }
        case .share:
            viewModel.share()
        case .quote:
            print("Quote action tapped for post: \(viewModel.post.id)")
        }
    }

    private func sendReply() {
        Task {
            do {
                let _ = try await serviceManager.replyToPost(viewModel.post, content: replyText)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isReplying = false
                        replyText = ""
                    }
                }
            } catch let replyError {
                print("Error sending reply: \(replyError)")
                await MainActor.run {
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
                    post: Post.samplePosts[0],
                    serviceManager: SocialServiceManager()
                ),
                focusReplyComposer: false
            )
            .environmentObject(SocialServiceManager())
            .environmentObject(PostNavigationEnvironment())
        }
    }
}
