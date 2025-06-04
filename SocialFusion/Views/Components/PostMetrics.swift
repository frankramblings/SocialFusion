import SwiftUI

/// A view that displays post engagement metrics
struct PostMetrics: View {
    let replyCount: Int
    let repostCount: Int
    let likeCount: Int
    let platform: SocialPlatform

    var body: some View {
        HStack(spacing: 16) {
            // Reply count
            MetricView(
                icon: "bubble.left",
                count: replyCount,
                color: platformColor
            )

            // Repost count
            MetricView(
                icon: "arrow.2.squarepath",
                count: repostCount,
                color: platformColor
            )

            // Like count
            MetricView(
                icon: "heart",
                count: likeCount,
                color: platformColor
            )
        }
    }

    private var platformColor: Color {
        switch platform {
        case .bluesky:
            return .blue
        case .mastodon:
            return .purple
        }
    }
}

/// A view that displays a single metric with an icon and count
private struct MetricView: View {
    let icon: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)

            Text(formatCount(count))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

// MARK: - Preview
struct PostMetrics_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Bluesky metrics
            PostMetrics(
                replyCount: 42,
                repostCount: 123,
                likeCount: 456,
                platform: .bluesky
            )

            // Mastodon metrics
            PostMetrics(
                replyCount: 1234,
                repostCount: 5678,
                likeCount: 9012,
                platform: .mastodon
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
