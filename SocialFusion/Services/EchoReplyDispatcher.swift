import Foundation

/// Outcome of an echoed reply dispatch — which targets succeeded and which
/// failed. Failures are surfaced to the UI so the user can retry the failed
/// side(s) without re-sending the successful side.
public struct EchoReplyResult: Equatable, Sendable {
    public let succeeded: Set<SocialPlatform>
    public let failed: Set<SocialPlatform>

    public init(succeeded: Set<SocialPlatform>, failed: Set<SocialPlatform>) {
        self.succeeded = succeeded
        self.failed = failed
    }
}

/// Surface-level errors the dispatcher can synthesize before invoking the
/// network. Today only one case is used — when the reply target's loaded
/// root post or signed-in account is missing — but it lives in the
/// dispatcher's namespace so call sites can switch on it without having to
/// pattern-match on `NSError`.
public enum EchoReplyError: Error, Equatable, Sendable {
    case missingContext
}

/// Dispatches a Fused reply to one or both networks in parallel via the
/// supplied closures.
///
/// The closure-based seam keeps this unit-testable: production callers
/// route the closures into `MastodonService.replyToPost` /
/// `BlueskyService.replyToPost`; tests inject deterministic stubs.
///
/// Each closure is invoked only if its platform is present in `targets`.
/// The two closures run concurrently via `async let` so a slow side never
/// blocks the other.
@MainActor
public func sendEchoedReply(
    targets: Set<SocialPlatform>,
    sendToMastodon: @escaping () async throws -> Void,
    sendToBluesky: @escaping () async throws -> Void
) async -> EchoReplyResult {
    async let mastoOutcome: Bool? = {
        guard targets.contains(.mastodon) else { return nil }
        do { try await sendToMastodon(); return true }
        catch { return false }
    }()
    async let bskyOutcome: Bool? = {
        guard targets.contains(.bluesky) else { return nil }
        do { try await sendToBluesky(); return true }
        catch { return false }
    }()

    let m = await mastoOutcome
    let b = await bskyOutcome

    var succeeded: Set<SocialPlatform> = []
    var failed: Set<SocialPlatform> = []
    if m == true { succeeded.insert(.mastodon) } else if m == false { failed.insert(.mastodon) }
    if b == true { succeeded.insert(.bluesky) } else if b == false { failed.insert(.bluesky) }
    return EchoReplyResult(succeeded: succeeded, failed: failed)
}
