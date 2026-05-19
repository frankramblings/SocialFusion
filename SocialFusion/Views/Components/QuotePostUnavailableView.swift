import SwiftUI

/// Placeholder rendered in place of a quoted post when the post cannot be
/// fetched (deleted, blocked, network failure, malformed response). Matches
/// the visual footprint of `QuotedPostView` so the parent post layout stays
/// stable on fallback.
public struct QuotePostUnavailableView: View {
    public enum Reason: Equatable {
        case deleted
        case blocked
        case network
        case malformed
        case unknown

        var headline: String {
            switch self {
            case .deleted:   return "This quoted post is no longer available"
            case .blocked:   return "This quoted post is from a blocked or private account"
            case .network:   return "Couldn't load the quoted post"
            case .malformed: return "This quoted post couldn't be displayed"
            case .unknown:   return "This quoted post is no longer available"
            }
        }

        var detail: String? {
            switch self {
            case .network: return "Tap the link to view it in your browser."
            case .deleted, .blocked, .malformed, .unknown: return nil
            }
        }

        var iconName: String {
            switch self {
            case .deleted, .unknown: return "trash.slash"
            case .blocked:           return "eye.slash"
            case .network:           return "wifi.slash"
            case .malformed:         return "exclamationmark.bubble"
            }
        }
    }

    let reason: Reason
    let originalURL: URL?
    let platform: SocialPlatform

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    public init(reason: Reason, originalURL: URL?, platform: SocialPlatform) {
        self.reason = reason
        self.originalURL = originalURL
        self.platform = platform
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: reason.iconName)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(reason.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                PlatformDot(platform: platform, size: 14, useLogo: true)
            }
            if let detail = reason.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = originalURL {
                Button {
                    openURL(url)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption2)
                        Text(url.absoluteString)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Open original link")
                .accessibilityHint(url.absoluteString)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(backgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(borderOverlay)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(reason.headline). \(platform.accessibilityLabel)."))
    }

    private var backgroundStyle: some View {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.035)
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                colorScheme == .dark
                    ? Color.white.opacity(0.12)
                    : Color.black.opacity(0.08),
                style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])
            )
    }
}
