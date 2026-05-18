import SwiftUI

public struct WatchedConversationsView: View {
    @EnvironmentObject var store: WatchedConversationStore
    @EnvironmentObject var fusedMomentStore: FusedMomentStore

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
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let momentID = conv.fusedMomentID,
                       fusedMomentStore.moments[momentID] != nil {
                        FusedGlyph(size: 16)
                    } else {
                        PlatformLogoBadge(platform: conv.platform, size: 16)
                    }
                    Text(conv.rootPostID)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(conv.watchedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .swipeActions {
                Button(role: .destructive) {
                    store.unwatch(rootPostID: conv.rootPostID)
                } label: {
                    Label("Unwatch", systemImage: "bell.slash")
                }
            }
        }
    }
}
