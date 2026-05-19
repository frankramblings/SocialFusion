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
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No watched conversations")
                .font(.headline)
            Text("Tap the menu on a post and choose Watch conversation to follow it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text(conv.watchedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
        if let preview = conv.summary?.contentPreview, !preview.isEmpty {
            return "\(scope) by \(who): \(preview)"
        }
        return "\(scope) by \(who)"
    }
}
