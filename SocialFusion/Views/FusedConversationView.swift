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
    /// Bumped after every successful send so a ScrollViewReader observer
    /// scrolls to the just-inserted reply. Only sends move this — thread
    /// fetches and replies streaming in don't, so a reader's scroll
    /// position is preserved while older content paginates.
    @State private var scrollToLatestTrigger: Int = 0

    public init(viewModel: FusedConversationViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    rootHeader
                    outageBanners
                    ForEach(viewModel.replies) { merged in
                        ReplyRow(post: merged.post)
                            .padding(.horizontal)
                            .id(merged.id)
                    }
                    if shouldShowSkeleton {
                        // Spec acceptance criterion ("skeleton scaffolding"):
                        // show placeholder rows while we have no real replies
                        // yet but at least one side is still in flight.
                        ForEach(0..<3, id: \.self) { _ in
                            ReplySkeletonRow()
                                .padding(.horizontal)
                        }
                    } else if viewModel.mastodonStatus == .loading || viewModel.blueskyStatus == .loading {
                        // Trailing spinner: replies have started arriving from
                        // one side; the other is still streaming.
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                                .accessibilityLabel(stillLoadingPlatformLabel)
                            Spacer()
                        }
                    } else if shouldShowEmptyState {
                        emptyReplyState
                            .padding(.horizontal)
                            .padding(.top, 24)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: scrollToLatestTrigger) { _, _ in
                // Only fires after a send (we never bump this on a thread
                // fetch). Scroll to the newest reply so the user sees the
                // outcome of the action they just took without hunting.
                guard let lastID = viewModel.replies.last?.id else { return }
                withAnimation(.easeOut(duration: 0.30)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
        .navigationTitle("Fused conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCompose = true
                } label: {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                }
                .disabled(!canReply)
                // Cmd+R opens the reply composer — standard iPad/Mac
                // convention for "reply." Matches Apple Mail and similar.
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel(canReply
                    ? "Reply to this Fused conversation"
                    : "Reply unavailable: neither side has loaded yet")
                .accessibilityHint(canReply
                    ? "Opens a composer where you can echo your reply to both networks."
                    : "")
            }
        }
        .sheet(isPresented: $showingCompose) {
            EchoComposeView(
                viewModel: EchoComposeViewModel(
                    moment: viewModel.moment,
                    initialTargets: dispatchableInitialTargets
                ),
                onSend: { text, targets in
                    await sendAndResolve(text: text, targets: targets)
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
                    await sendAndResolve(text: ctx.text, targets: failed)
                }
            }
            Button("Dismiss", role: .cancel) {
                lastReplyFailures = []
            }
        } message: { failed in
            Text(replyFailureMessage(for: failed))
        }
        .onChange(of: viewModel.mastodonStatus) { _, new in
            // Subtle warning haptic when a side announces failure. iOS
            // standard for "your action surfaced a problem" rendered as a
            // banner. The banner itself reads as an alert region; the
            // haptic gives screen-off / Dynamic-Type users a cue too.
            if case .failed = new { HapticEngine.warning.trigger() }
        }
        .onChange(of: viewModel.blueskyStatus) { _, new in
            if case .failed = new { HapticEngine.warning.trigger() }
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

    /// A reply can be sent if at least one side has a resolved root post.
    /// When both sides are still loading or both failed, opening the
    /// composer would only lead to a dead-end preflight-fail dispatch —
    /// disable the toolbar Reply button so the affordance matches reality.
    private var canReply: Bool {
        viewModel.mastodonRootPost != nil || viewModel.blueskyRootPost != nil
    }

    /// Thin wrapper around the shared
    /// `SocialServiceManager.activeAccount(on:)` helper, kept for call-site
    /// readability inside this view.
    private func activeAccount(on platform: SocialPlatform) -> SocialAccount? {
        serviceManager.activeAccount(on: platform)
    }

    /// Initial Echo target set, intersected with what we can actually
    /// dispatch to: an account exists *and* the root post for that
    /// network has loaded. Without this, a Mastodon-only user opening
    /// a Fused conversation would land on the composer with Bluesky
    /// pre-checked under `echoOn` policy — a confusing default that
    /// would also fail preflight on Send. Echoes only the policy's
    /// intent within the user's actual reach.
    private var dispatchableInitialTargets: Set<SocialPlatform> {
        let policyTargets = echoPolicyStore.initialReplyTargets(
            originalPlatform: viewModel.rootPost?.platform ?? .mastodon
        )
        var available: Set<SocialPlatform> = []
        if !serviceManager.mastodonAccounts.isEmpty,
           viewModel.mastodonRootPost != nil {
            available.insert(.mastodon)
        }
        if !serviceManager.blueskyAccounts.isEmpty,
           viewModel.blueskyRootPost != nil {
            available.insert(.bluesky)
        }
        return policyTargets.intersection(available)
    }

    /// Tells VoiceOver which side is still streaming when only one
    /// network's replies have arrived. Without this label, the trailing
    /// ProgressView is silent — the user has no idea more replies are
    /// inbound until they appear.
    private var stillLoadingPlatformLabel: String {
        let mastoLoading = viewModel.mastodonStatus == .loading
        let bskyLoading = viewModel.blueskyStatus == .loading
        if mastoLoading && bskyLoading {
            return "Loading more replies"
        }
        if mastoLoading {
            return "Loading more Mastodon replies"
        }
        if bskyLoading {
            return "Loading more Bluesky replies"
        }
        return "Loading more replies"
    }

    private var shouldShowSkeleton: Bool {
        guard viewModel.replies.isEmpty else { return false }
        return viewModel.mastodonStatus == .loading || viewModel.blueskyStatus == .loading
    }

    /// True when both sides finished loading (loaded or failed) and produced
    /// no replies. We treat "failed on both sides" as outage rather than
    /// emptiness — the outage banners already speak to that case.
    private var shouldShowEmptyState: Bool {
        guard viewModel.replies.isEmpty else { return false }
        let bothNotLoading = viewModel.mastodonStatus != .loading && viewModel.blueskyStatus != .loading
        guard bothNotLoading else { return false }
        // If neither side actually loaded successfully, this is an outage,
        // not an empty conversation — banners handle it.
        let anyLoaded = viewModel.mastodonStatus == .loaded || viewModel.blueskyStatus == .loaded
        return anyLoaded
    }

    private var emptyReplyState: some View {
        VStack(spacing: 8) {
            FusedGlyph(size: 28, bloomOnAppear: false)
            Text("No replies yet on either side.")
                .font(.subheadline.weight(.semibold))
            Text("Be the first to reply — your reply can echo to both networks.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No replies yet on either Mastodon or Bluesky. Be the first to reply.")
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

    /// Single funnel for both the initial send and the failure-alert
    /// Retry: dispatches, then resolves all post-send side effects
    /// (haptics, scroll trigger, failure-alert state, retry-context
    /// bookkeeping) consistently. Keeps initial-send and retry from
    /// drifting apart on what feels "complete" to the user.
    private func sendAndResolve(text: String, targets: Set<SocialPlatform>) async {
        let result = await dispatchEchoedReply(text: text, targets: targets)
        lastReplyContext = (text: text, targets: targets)
        lastReplyFailures = result.failed
        if result.failed.isEmpty {
            HapticEngine.success.trigger()
        } else if !result.succeeded.isEmpty {
            HapticEngine.warning.trigger()
        } else {
            HapticEngine.error.trigger()
        }
        if !result.succeeded.isEmpty {
            scrollToLatestTrigger &+= 1
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
        // Prefer the timeline-selected account so users with multiple
        // accounts on the same network reply from the one they're
        // currently reading on, not from an arbitrary `.first`. Fall
        // back to `.first` for the unified-feed case where there's no
        // single active account.
        let mastoAccount = activeAccount(on: .mastodon)
            ?? serviceManager.mastodonAccounts.first
        let bskyAccount = activeAccount(on: .bluesky)
            ?? serviceManager.blueskyAccounts.first
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

        // Bridge into a non-mutating local so the @Sendable-ish closure
        // captures don't need to reference the SwiftUI View's @StateObject
        // directly — `viewModel` here is a stable reference, but reading
        // through `self` from inside an escaping closure trips actor
        // checks in strict-concurrency mode. The local capture is enough
        // to keep this on MainActor cleanly.
        let vm = viewModel

        let result = await sendEchoedReply(
            targets: dispatchable,
            sendToMastodon: { [text] in
                guard let post = mastoRoot, let account = mastoAccount else {
                    throw EchoReplyError.missingContext
                }
                let sent = try await mastoService.replyToPost(
                    post,
                    content: text,
                    account: account
                )
                // Optimistic insertion: the new reply lands in the merged
                // stream immediately, so the user sees their own reply
                // without waiting for the next thread fetch.
                vm.insertSentReply(sent)
            },
            sendToBluesky: { [text] in
                guard let post = bskyRoot, let account = bskyAccount else {
                    throw EchoReplyError.missingContext
                }
                let sent = try await bskyService.replyToPost(
                    post,
                    content: text,
                    account: account
                )
                vm.insertSentReply(sent)
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
            return "\(p.accessibilityLabel) reply didn't go through"
        default: return "Reply failed"
        }
    }

    private func replyFailureMessage(for failed: Set<SocialPlatform>) -> String {
        let names = failed
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.accessibilityLabel)
            .joined(separator: " and ")
        return "Your reply to \(names) couldn't be sent. Tap Retry to try \(failed.count == 2 ? "them" : "it") again."
    }

    private func outageBanner(platform: SocialPlatform, message: String, retry: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            PlatformLogoBadge(platform: platform, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(platform.accessibilityLabel) replies didn't load")
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
            // The viewModel's dismissedFailureBanners set was previously
            // read but never written — there was no path to hide the
            // banner if the user wasn't going to retry. Closes that
            // gap. Once dismissed the banner stays hidden until the
            // next `load()` / `retry()` clears the dismissal.
            Button {
                viewModel.dismissedFailureBanners.insert(platform)
                HapticEngine.selection.trigger()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss banner")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        // `.combine` previously swallowed the Retry button so VoiceOver
        // users got the announcement but no way to act on it. `.contain`
        // keeps the banner as one logical group while preserving the
        // Retry button as its own focusable element; the custom action
        // also exposes Retry through the VoiceOver rotor so it's
        // reachable without hunting for the visible button.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(platform.accessibilityLabel) replies failed to load. \(message)")
        .accessibilityAction(named: "Retry", retry)
    }
}

/// Compact rendering of the root post at the top of the conversation.
/// Intentionally light — not a full `PostCardView` because the conversation
/// header doesn't need the action bar (replies appear below).
///
/// Shows **both** platform badges side-by-side, never just the network whose
/// thread happened to resolve first. The root of a Fused conversation
/// belongs to both networks by definition — single-badging it would
/// silently re-introduce the "Mastodon detail vs. Bluesky detail" framing
/// the Fuse exists to dissolve.
private struct RootPostHeader: View {
    let post: Post

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(post.authorName)
                        .font(.subheadline.weight(.semibold))
                    bothNetworkBadges
                    Spacer(minLength: 0)
                    Text(post.createdAt.relativeTimeString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                // Use PostContent so Mastodon HTML is stripped and
                // hashtags / mentions get the standard tinted styling.
                // Without this, root posts from Mastodon rendered the
                // raw `<p>…</p>` tags as visible text — a glaring
                // polish miss right at the top of the conversation,
                // which is supposed to be the unit of attention.
                PostContent(
                    content: post.content,
                    hashtags: post.tags,
                    mentions: post.mentions,
                    onHashtagTap: { _ in },
                    onMentionTap: { _ in }
                )
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var bothNetworkBadges: some View {
        HStack(spacing: 2) {
            PlatformLogoBadge(platform: .mastodon, size: 14)
            PlatformLogoBadge(platform: .bluesky, size: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Posted on both Mastodon and Bluesky")
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

/// Placeholder reply shown while the thread is loading and no real replies
/// have arrived yet. Matches `ReplyRow`'s geometry so the layout doesn't
/// jump when the first reply lands. Animates with a soft shimmer; honored
/// by reduce-motion (no animation when the user has it on).
private struct ReplySkeletonRow: View {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 6) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 120, height: 12)
                Capsule()
                    .fill(Color.secondary.opacity(0.14))
                    .frame(maxWidth: .infinity)
                    .frame(height: 12)
                Capsule()
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 180, height: 12)
            }
        }
        .opacity(0.85 - 0.25 * abs(phase))
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
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
                    Spacer(minLength: 0)
                    Text(post.createdAt.relativeTimeString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                // Same reason as RootPostHeader: a bare Text(post.content)
                // renders raw <p>…</p> from Mastodon replies. Routing
                // through PostContent strips HTML and keeps hashtag /
                // mention styling consistent with the rest of the app.
                PostContent(
                    content: post.content,
                    hashtags: post.tags,
                    mentions: post.mentions,
                    onHashtagTap: { _ in },
                    onMentionTap: { _ in }
                )
            }
        }
        // Combine into a single VoiceOver element so a swipe lands one
        // reply at a time, not four sub-elements (avatar/author/badge/time
        // sub-swipes felt fiddly). Custom label spells out the network
        // since the PlatformLogoBadge is no longer separately readable.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let networkName = post.platform.accessibilityLabel
        let formatter = RelativeDateTimeFormatter()
        let when = formatter.localizedString(for: post.createdAt, relativeTo: Date())
        // Strip HTML for VoiceOver too — otherwise Mastodon replies are
        // read out as "less than p greater than … less than slash p
        // greater than", which is unintelligible. Uses the canonical
        // String+HTML extensions instead of inlining the strip so the
        // entity table stays in one place.
        let plain = post.content
            .strippingHTMLTags
            .decodingHTMLEntities
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(networkName) reply from \(post.authorName), \(when): \(plain)"
    }
}
