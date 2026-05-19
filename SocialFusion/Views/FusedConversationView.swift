import SwiftUI

public struct FusedConversationView: View {
    @StateObject var viewModel: FusedConversationViewModel
    @EnvironmentObject private var echoPolicyStore: EchoPolicyStore
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @State private var didLoad = false
    @State private var showingCompose = false
    /// Platforms that failed in the most recent send. Drives the
    /// post-send failure alert; empty set means no failure to surface.
    @State private var lastReplyFailures: Set<SocialPlatform> = []
    /// The text + target set from the most recent send, kept so the
    /// "Retry" action in the failure alert can re-dispatch only to the
    /// failed side(s) without re-sending the already-successful side.
    @State private var lastReplyContext: (text: String, targets: Set<SocialPlatform>)? = nil

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCompose = true
                } label: {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .accessibilityLabel("Reply to this conversation")
                }
            }
        }
        .sheet(isPresented: $showingCompose) {
            EchoComposeView(
                viewModel: EchoComposeViewModel(
                    moment: viewModel.moment,
                    initialTargets: echoPolicyStore.initialReplyTargets(
                        originalPlatform: viewModel.rootPost?.platform ?? .mastodon
                    )
                ),
                onSend: { text, targets in
                    let result = await dispatchEchoedReply(
                        text: text,
                        targets: targets
                    )
                    lastReplyContext = (text: text, targets: targets)
                    lastReplyFailures = result.failed
                }
            )
        }
        .alert(
            replyFailureTitle,
            isPresented: Binding(
                get: { !lastReplyFailures.isEmpty },
                set: { if !$0 { lastReplyFailures = [] } }
            ),
            presenting: lastReplyFailures
        ) { failed in
            Button("Retry") {
                guard let ctx = lastReplyContext else { return }
                Task {
                    let result = await dispatchEchoedReply(
                        text: ctx.text,
                        targets: failed
                    )
                    lastReplyFailures = result.failed
                }
            }
            Button("Dismiss", role: .cancel) {
                lastReplyFailures = []
            }
        } message: { failed in
            Text(replyFailureMessage(for: failed))
        }
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

    /// Dispatches a Fused reply to the requested target platforms.
    ///
    /// Looks up the loaded root post and the first account for each
    /// requested platform. If either is missing (one side hasn't loaded,
    /// or the user has no account on that platform), that side is
    /// reported as a failure without invoking the API — the user can
    /// still see which side didn't go through.
    private func dispatchEchoedReply(
        text: String,
        targets: Set<SocialPlatform>
    ) async -> EchoReplyResult {
        let mastoRoot = viewModel.mastodonRootPost
        let bskyRoot = viewModel.blueskyRootPost
        let mastoAccount = serviceManager.mastodonAccounts.first
        let bskyAccount = serviceManager.blueskyAccounts.first
        let mastoService = serviceManager.mastodonService
        let bskyService = serviceManager.blueskyService

        // Pre-flight: if a target lacks a loaded root post or an account,
        // we can't send. Synthesize a failure for that side and exclude
        // it from the parallel dispatch so we don't call into the
        // services with bad inputs.
        var preflightFailures: Set<SocialPlatform> = []
        var dispatchable = targets
        if targets.contains(.mastodon), mastoRoot == nil || mastoAccount == nil {
            preflightFailures.insert(.mastodon)
            dispatchable.remove(.mastodon)
        }
        if targets.contains(.bluesky), bskyRoot == nil || bskyAccount == nil {
            preflightFailures.insert(.bluesky)
            dispatchable.remove(.bluesky)
        }

        let result = await sendEchoedReply(
            targets: dispatchable,
            sendToMastodon: { [text] in
                guard let post = mastoRoot, let account = mastoAccount else {
                    throw EchoReplyError.missingContext
                }
                _ = try await mastoService.replyToPost(
                    post,
                    content: text,
                    account: account
                )
            },
            sendToBluesky: { [text] in
                guard let post = bskyRoot, let account = bskyAccount else {
                    throw EchoReplyError.missingContext
                }
                _ = try await bskyService.replyToPost(
                    post,
                    content: text,
                    account: account
                )
            }
        )

        return EchoReplyResult(
            succeeded: result.succeeded,
            failed: result.failed.union(preflightFailures)
        )
    }

    private var replyFailureTitle: String {
        switch lastReplyFailures.count {
        case 2: return "Reply didn't go through"
        case 1:
            let p = lastReplyFailures.first!
            return "\(p == .mastodon ? "Mastodon" : "Bluesky") reply didn't go through"
        default: return "Reply failed"
        }
    }

    private func replyFailureMessage(for failed: Set<SocialPlatform>) -> String {
        let names = failed
            .sorted { $0.rawValue < $1.rawValue }
            .map { $0 == .mastodon ? "Mastodon" : "Bluesky" }
            .joined(separator: " and ")
        return "Your reply to \(names) couldn't be sent. Tap Retry to try \(failed.count == 2 ? "them" : "it") again."
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
