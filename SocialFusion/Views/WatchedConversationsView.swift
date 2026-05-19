import SwiftUI

public struct WatchedConversationsView: View {
    @EnvironmentObject var store: WatchedConversationStore
    @EnvironmentObject var fusedMomentStore: FusedMomentStore
    @EnvironmentObject var serviceManager: SocialServiceManager

    public init() {}

    public var body: some View {
        Group {
            if store.allWatched().isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .navigationTitle("Watching")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            // FusedGlyph instead of `bell.slash`: the feature is cross-
            // network thread-following — the glyph carries that meaning
            // more honestly than a generic notification icon.
            FusedGlyph(size: 48, bloomOnAppear: false)
            Text("Nothing watched yet")
                .font(.headline)
            Text("Watch a conversation to get a ping when someone replies on either network. Open a post's menu and pick **Watch conversation**.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nothing watched yet. Watch a conversation to get a ping when someone replies on either network. Open a post's menu and pick Watch conversation.")
    }

    private var listContent: some View {
        List(store.allWatched()) { conv in
            rowContent(for: conv)
                .swipeActions {
                    Button(role: .destructive) {
                        store.unwatch(rootPostID: conv.rootPostID)
                        HapticEngine.selection.trigger()
                    } label: {
                        Label("Unwatch", systemImage: "bell.slash")
                    }
                }
        }
    }

    /// A Fused watched row pushes into `FusedConversationView`; non-Fused
    /// rows stay informational for v1.0 (no per-network thread destination
    /// is wired from Settings yet).
    @ViewBuilder
    private func rowContent(for conv: WatchedConversation) -> some View {
        if let momentID = conv.fusedMomentID,
           let moment = fusedMomentStore.moments[momentID] {
            NavigationLink {
                FusedConversationView(
                    viewModel: FusedConversationViewModel(
                        moment: moment,
                        threadFetcher: SocialServiceManagerThreadFetcher(serviceManager: serviceManager)
                    )
                )
            } label: {
                row(for: conv)
            }
        } else {
            row(for: conv)
        }
    }

    @ViewBuilder
    private func row(for conv: WatchedConversation) -> some View {
        let isFused = conv.fusedMomentID.flatMap { fusedMomentStore.moments[$0] } != nil
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if isFused {
                    FusedGlyph(size: 16)
                } else {
                    PlatformLogoBadge(platform: conv.platform, size: 16)
                }
                Text(conv.summary?.authorName ?? fallbackTitle(for: conv))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                // Match the Twitter-style abbreviated cadence used in
                // FusedConversationView ("2m", "3h") instead of the
                // verbose "2 minutes ago" SwiftUI produces by default —
                // visual consistency with the rest of the app, plus
                // monospaced digits so the number doesn't shimmer when
                // it ticks. VoiceOver gets a friendlier expansion via
                // the combined label below.
                Text(conv.watchedAt.relativeTimeString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let preview = conv.summary?.contentPreview, !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: conv, isFused: isFused))
    }

    /// Fallback title used when an older watched record was persisted before
    /// `summary` existed. Still useful — communicates the network — but the
    /// author name is preferred when present.
    private func fallbackTitle(for conv: WatchedConversation) -> String {
        switch conv.platform {
        case .mastodon: return "Conversation on Mastodon"
        case .bluesky: return "Conversation on Bluesky"
        }
    }

    private func accessibilityLabel(for conv: WatchedConversation, isFused: Bool) -> String {
        let who = conv.summary?.authorName ?? fallbackTitle(for: conv)
        let scope = isFused ? "Fused conversation" : (conv.platform == .mastodon ? "Mastodon conversation" : "Bluesky conversation")
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let when = "watched \(formatter.localizedString(for: conv.watchedAt, relativeTo: Date()))"
        if let preview = conv.summary?.contentPreview, !preview.isEmpty {
            return "\(scope) by \(who): \(preview), \(when)"
        }
        return "\(scope) by \(who), \(when)"
    }
}
