import SwiftUI

public struct FusedConversationView: View {
    @StateObject var viewModel: FusedConversationViewModel
    @State private var didLoad = false

    public init(viewModel: FusedConversationViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                rootHeader
                outageBanners
                ForEach(viewModel.replies) { merged in
                    ReplyRow(post: merged.post)
                        .padding(.horizontal)
                }
                if viewModel.mastodonStatus == .loading || viewModel.blueskyStatus == .loading {
                    HStack { Spacer(); ProgressView().padding(); Spacer() }
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle("Fused conversation")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !didLoad else { return }
            didLoad = true
            await viewModel.load()
        }
    }

    private var rootHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                FusedGlyph(size: 18, bloomOnAppear: false)
                Text("Fused conversation")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let root = viewModel.rootPost {
                RootPostHeader(post: root)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var outageBanners: some View {
        if case .failed(let msg) = viewModel.mastodonStatus,
           !viewModel.dismissedFailureBanners.contains(.mastodon) {
            outageBanner(platform: .mastodon, message: msg) {
                Task { await viewModel.retry(.mastodon) }
            }
        }
        if case .failed(let msg) = viewModel.blueskyStatus,
           !viewModel.dismissedFailureBanners.contains(.bluesky) {
            outageBanner(platform: .bluesky, message: msg) {
                Task { await viewModel.retry(.bluesky) }
            }
        }
    }

    private func outageBanner(platform: SocialPlatform, message: String, retry: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            PlatformLogoBadge(platform: platform, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(platform == .mastodon ? "Mastodon" : "Bluesky") replies didn't load")
                    .font(.footnote.weight(.semibold))
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(platform == .mastodon ? "Mastodon" : "Bluesky") replies failed to load. \(message)")
    }
}

/// Compact rendering of the root post at the top of the conversation.
/// Intentionally light — not a full `PostCardView` because the conversation
/// header doesn't need the action bar (replies appear below).
private struct RootPostHeader: View {
    let post: Post

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(post.authorName)
                        .font(.subheadline.weight(.semibold))
                    PlatformLogoBadge(platform: post.platform, size: 14)
                    Spacer(minLength: 0)
                    Text(post.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(post.content)
                    .font(.body)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var avatar: some View {
        AsyncImage(url: URL(string: post.authorProfilePictureURL)) { img in
            img.resizable()
        } placeholder: {
            Circle().fill(Color.gray.opacity(0.2))
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }
}

/// Single reply row in the merged stream. Each reply carries its platform
/// badge so the network is always visible — color + shape (PlatformLogoBadge).
private struct ReplyRow: View {
    let post: Post

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: URL(string: post.authorProfilePictureURL)) { img in
                img.resizable()
            } placeholder: {
                Circle().fill(Color.gray.opacity(0.2))
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(post.authorName)
                        .font(.subheadline.weight(.semibold))
                    PlatformLogoBadge(platform: post.platform, size: 14)
                        .accessibilityLabel(post.platform == .mastodon ? "Mastodon" : "Bluesky")
                    Spacer(minLength: 0)
                    Text(post.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(post.content)
                    .font(.body)
            }
        }
    }
}
