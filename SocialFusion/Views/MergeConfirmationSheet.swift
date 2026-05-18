import SwiftUI

/// Sheet that asks the user to confirm a heuristic merge candidate.
///
/// Used only for `.handleConvention` provenance — verified bio cross-links
/// auto-apply without asking. User-confirmed merges persist; "Not the same
/// person" inserts a tombstone via `unmerge(id:)` semantics.
public struct MergeConfirmationSheet: View {
    public let candidate: MergedIdentity
    public let mastodonAvatarURL: String?
    public let blueskyAvatarURL: String?
    public let onConfirm: () -> Void
    public let onReject: () -> Void
    public let onDismiss: () -> Void

    public init(
        candidate: MergedIdentity,
        mastodonAvatarURL: String?,
        blueskyAvatarURL: String?,
        onConfirm: @escaping () -> Void,
        onReject: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.candidate = candidate
        self.mastodonAvatarURL = mastodonAvatarURL
        self.blueskyAvatarURL = blueskyAvatarURL
        self.onConfirm = onConfirm
        self.onReject = onReject
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 20) {
            header
            pairSummary
            reasonLine
            Spacer(minLength: 0)
            actions
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(spacing: 6) {
            MergedIdentityChip(provenance: candidate.provenance)
            Text("Looks like the same person")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Confirm to view both profiles as one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var pairSummary: some View {
        HStack(spacing: 12) {
            sideCard(
                platform: .mastodon,
                handle: candidate.mastodon.handle,
                avatarURL: mastodonAvatarURL
            )
            Image(systemName: "arrow.left.and.right")
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            sideCard(
                platform: .bluesky,
                handle: candidate.bluesky.handle,
                avatarURL: blueskyAvatarURL
            )
        }
    }

    private func sideCard(platform: SocialPlatform, handle: String, avatarURL: String?) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                avatarView(urlString: avatarURL)
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                PlatformLogoBadge(platform: platform, size: 22)
                    .offset(x: 2, y: 2)
            }
            Text("@\(handle)")
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(platform.rawValue.capitalized): at \(handle)")
    }

    @ViewBuilder
    private func avatarView(urlString: String?) -> some View {
        if let urlString = urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle().fill(Color(.secondarySystemBackground))
            }
        } else {
            Circle().fill(Color(.secondarySystemBackground))
                .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
        }
    }

    private var reasonLine: some View {
        let reason: String = {
            switch candidate.provenance {
            case .handleConvention:
                return "Both handles share \"@\(localPart(candidate.mastodon.handle))\" on conventional domains."
            case .verifiedBioCrossLink:
                return "Each profile's bio verifiably links to the other."
            case .userConfirmed:
                return "You confirmed this merge."
            }
        }()
        return Text(reason)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    private func localPart(_ handle: String) -> String {
        if let at = handle.firstIndex(of: "@") {
            return String(handle[..<at])
        }
        if let dot = handle.firstIndex(of: ".") {
            return String(handle[..<dot])
        }
        return handle
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: onConfirm) {
                Text("Confirm merge")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            Button(action: onReject) {
                Text("Not the same person")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            Button("Decide later", action: onDismiss)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
struct MergeConfirmationSheet_Previews: PreviewProvider {
    static var previews: some View {
        MergeConfirmationSheet(
            candidate: MergedIdentity(
                mastodon: MergedIdentityKey(platform: .mastodon, accountID: "m1", handle: "gruber@mastodon.social"),
                bluesky: MergedIdentityKey(platform: .bluesky, accountID: "b1", handle: "gruber.bsky.social"),
                provenance: .handleConvention,
                confidence: 0.78
            ),
            mastodonAvatarURL: nil,
            blueskyAvatarURL: nil,
            onConfirm: {}, onReject: {}, onDismiss: {}
        )
    }
}
#endif
