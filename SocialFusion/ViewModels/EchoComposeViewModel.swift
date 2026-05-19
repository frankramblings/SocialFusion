import Combine
import Foundation
import SwiftUI

@MainActor
public final class EchoComposeViewModel: ObservableObject {
    public let moment: FusedMoment

    @Published public var text: String = ""
    @Published public var targets: Set<SocialPlatform>
    @Published public private(set) var isSending: Bool = false

    /// Platforms the user can actually dispatch to — driven by which
    /// accounts they have signed in. The composer disables target
    /// toggles outside this set so a user with only Mastodon can't
    /// flip Bluesky on and watch the Send fail. Defaults to both for
    /// callers that don't care (e.g., older tests).
    public let availablePlatforms: Set<SocialPlatform>

    /// Called by the view at the start of a send so the Send button can be
    /// disabled and the UI can reflect the in-flight state. Paired with
    /// `finishSending()` to guarantee the flag is cleared even on failure.
    public func beginSending() { isSending = true }
    public func finishSending() { isSending = false }

    public init(
        moment: FusedMoment,
        initialTargets: Set<SocialPlatform>,
        availablePlatforms: Set<SocialPlatform> = [.mastodon, .bluesky]
    ) {
        self.moment = moment
        self.targets = initialTargets
        self.availablePlatforms = availablePlatforms
    }

    public var mastodonLimit: Int { 500 }
    public var blueskyLimit: Int { 300 }

    public var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var mastodonRemaining: Int { mastodonLimit - text.count }
    public var blueskyRemaining: Int { blueskyLimit - text.count }

    public var canSend: Bool {
        guard !isSending else { return false }
        guard !trimmedText.isEmpty else { return false }
        guard !targets.isEmpty else { return false }
        if targets.contains(.mastodon) && mastodonRemaining < 0 { return false }
        if targets.contains(.bluesky) && blueskyRemaining < 0 { return false }
        return true
    }

    public var sendActionLabel: String {
        switch targets {
        case []: return "Reply…"
        case [.mastodon]: return "Reply on Mastodon"
        case [.bluesky]: return "Reply on Bluesky"
        case [.mastodon, .bluesky]: return "Reply to both"
        default: return "Reply…"
        }
    }

    public enum SendStyle {
        case dual, mastodonOnly, blueskyOnly, disabled
    }

    public var sendStyle: SendStyle {
        switch targets {
        case [.mastodon, .bluesky]: return .dual
        case [.mastodon]: return .mastodonOnly
        case [.bluesky]: return .blueskyOnly
        default: return .disabled
        }
    }
}
