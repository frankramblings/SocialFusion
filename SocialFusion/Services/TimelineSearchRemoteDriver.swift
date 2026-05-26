import Foundation

/// Thin wrapper around `SearchProviding` that adapts the timeline-search
/// VM's needs (text + context) into a `SearchQuery` and unwraps the result
/// into `TimelineSearchHit` values keyed by their platform of origin.
public final class TimelineSearchRemoteDriver {

    private let provider: SearchProviding

    public init(provider: SearchProviding) {
        self.provider = provider
    }

    /// Runs a single search. Returns hits in the order the provider returned
    /// them; callers are expected to group by platform for presentation.
    /// An empty/whitespace-only `text` short-circuits with zero hits and no
    /// network call.
    public func search(
        text: String,
        context: TimelineSearchContext
    ) async throws -> [TimelineSearchHit] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let query = SearchQuery(
            text: trimmed,
            scope: .posts,
            networkSelection: networkSelection(for: context),
            sort: .latest,
            timeWindow: nil
        )

        let page = try await provider.searchPosts(query: query, page: nil)
        return page.items.compactMap { item -> TimelineSearchHit? in
            guard case .post(let post) = item else { return nil }
            return TimelineSearchHit(post: post, source: .remote(platform: post.platform))
        }
    }

    private func networkSelection(for context: TimelineSearchContext) -> SearchNetworkSelection {
        let platforms = context.platforms
        if platforms == Set(SocialPlatform.allCases) {
            return .unified
        }
        if platforms == [.mastodon] {
            return .mastodon
        }
        if platforms == [.bluesky] {
            return .bluesky
        }
        return .unified
    }
}
