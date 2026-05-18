import SwiftUI

/// A horizontal two-segment selector for a merged profile's handles.
///
/// Both handles are always visible — the merge is the point — but tapping a
/// segment swaps which side drives the bio, fields, and banner display in
/// the surrounding `ProfileHeaderView`.
public struct MergedHandleSelector: View {
    public let mastodonHandle: String
    public let blueskyHandle: String
    @Binding public var selected: SocialPlatform

    public init(
        mastodonHandle: String,
        blueskyHandle: String,
        selected: Binding<SocialPlatform>
    ) {
        self.mastodonHandle = mastodonHandle
        self.blueskyHandle = blueskyHandle
        self._selected = selected
    }

    public var body: some View {
        HStack(spacing: 8) {
            handleSegment(
                platform: .mastodon,
                handle: mastodonHandle,
                isSelected: selected == .mastodon
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selected = .mastodon
                }
            }

            handleSegment(
                platform: .bluesky,
                handle: blueskyHandle,
                isSelected: selected == .bluesky
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selected = .bluesky
                }
            }
        }
    }

    private func handleSegment(
        platform: SocialPlatform,
        handle: String,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 6) {
            PlatformLogoBadge(platform: platform, size: 18, shadowEnabled: false)
            Text("@\(handle)")
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color(.secondarySystemBackground) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isSelected ? Color.primary.opacity(0.15) : Color.clear,
                    lineWidth: 0.5
                )
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(platform.rawValue.capitalized) handle, at \(handle)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

#if DEBUG
struct MergedHandleSelector_Previews: PreviewProvider {
    struct Wrapper: View {
        @State var selected: SocialPlatform = .mastodon
        var body: some View {
            MergedHandleSelector(
                mastodonHandle: "gruber@mastodon.social",
                blueskyHandle: "gruber.bsky.social",
                selected: $selected
            )
            .padding()
        }
    }
    static var previews: some View {
        Wrapper()
    }
}
#endif
