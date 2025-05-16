import SwiftUI

/// Post action types
enum PostAction {
    case reply
    case repost
    case like
    case share
}

/// A view that displays a post in the timeline
struct PostCardView: View {
    let post: Post
    @State private var showDetailView = false
    @EnvironmentObject var serviceManager: SocialServiceManager

    @ViewBuilder
    private var headerSection: some View {
        // --- POST HEADER START ---
        HStack {
            AsyncImage(url: URL(string: post.authorProfilePictureURL)) { phase in
                if let image = phase.image {
                    image.resizable()
                } else if phase.error != nil {
                    Color.gray.opacity(0.3)
                } else {
                    Color.gray.opacity(0.1)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(post.authorName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Circle()
                        .fill(post.platform.color)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.1), radius: 1)
                }
                HStack {
                    Text("@\(post.authorUsername)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(post.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        // --- POST HEADER END ---
    }

    @ViewBuilder
    private var mediaSection: some View {
        // --- MEDIA ATTACHMENTS START ---
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
            ForEach(post.attachments.prefix(4), id: \.id) { attachment in
                AsyncImage(url: URL(string: attachment.url)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(Color.gray.opacity(0.2))
                    }
                }
                .frame(maxHeight: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(contentMode: .fit)
        .cornerRadius(8)
        // --- MEDIA ATTACHMENTS END ---
    }

    @ViewBuilder
    private var actionsSection: some View {
        ActionBar(post: post, onAction: handleAction)
    }

    var body: some View {
        cardBody
    }

    @ViewBuilder
    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection

            // Content with link previews for timeline view
            if !post.content.isEmpty {
                post.contentView(showLinkPreview: true)
            }

            if !post.attachments.isEmpty {
                mediaSection
            }

            actionsSection
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .onTapGesture {
            showDetailView = true
        }
        .sheet(isPresented: $showDetailView) {
            PostDetailSheet(post: post, dismiss: { showDetailView = false })
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
                // Show reply UI
                showDetailView = true
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
}

// MARK: - PostDetailSheet
struct PostDetailSheet: View {
    let post: Post
    let dismiss: () -> Void

    var body: some View {
        NavigationView {
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
                        Circle()
                            .fill(post.platform.color)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 0)
                    }

                    // Post content
                    if !post.content.isEmpty {
                        post.contentView(showLinkPreview: true)
                    }

                    // Media attachments
                    if !post.attachments.isEmpty {
                        // Simple grid layout for media
                        mediaGrid
                    }

                    // Post metadata
                    postMetadata
                }
                .padding()
            }
            .navigationTitle("Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var mediaGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4
        ) {
            ForEach(post.attachments.prefix(4), id: \.id) { attachment in
                AsyncImage(url: URL(string: attachment.url)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                    }
                }
                .frame(maxHeight: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(contentMode: .fit)
        .cornerRadius(8)
    }

    @ViewBuilder
    private var postMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Timestamp
            Text(post.createdAt, style: .date)
                .font(.footnote)
                .foregroundColor(.secondary)

            // Stats
            HStack(spacing: 12) {
                if post.repostCount > 0 {
                    Label(
                        "\(post.repostCount) Reposts",
                        systemImage: "arrow.2.squarepath")
                }

                if post.likeCount > 0 {
                    Label("\(post.likeCount) Likes", systemImage: "heart")
                }
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview
struct PostCardView_Previews: PreviewProvider {
    static var previews: some View {
        PostCardView(post: Post.samplePosts[0])
            .environmentObject(SocialServiceManager())
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
