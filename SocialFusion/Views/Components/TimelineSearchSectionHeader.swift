import SwiftUI

struct TimelineSearchSectionHeader: View {

    enum Kind: Equatable {
        case client
        case remote(platform: SocialPlatform)
    }

    let kind: Kind
    let resultCount: Int

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 18, height: 18)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(resultCount)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("\(resultCount) results"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder private var icon: some View {
        switch kind {
        case .client:
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
        case .remote(let platform):
            PlatformLogoBadge(platform: platform, size: 18)
        }
    }

    private var title: String {
        switch kind {
        case .client:
            return "Already in your timeline"
        case .remote(let platform):
            switch platform {
            case .mastodon: return "From Mastodon"
            case .bluesky: return "From Bluesky"
            }
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        TimelineSearchSectionHeader(kind: .client, resultCount: 3)
        TimelineSearchSectionHeader(kind: .remote(platform: .mastodon), resultCount: 12)
        TimelineSearchSectionHeader(kind: .remote(platform: .bluesky), resultCount: 7)
    }
}
