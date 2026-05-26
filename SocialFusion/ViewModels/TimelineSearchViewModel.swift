import Foundation
import Combine

/// Drives the two-layer timeline search experience.
///
/// Layer 1 (client): in-memory filter over a snapshot of the timeline buffer.
/// Layer 2 (remote): async fan-out to `SearchProviding` via the remote driver.
///
/// Both layers feed into `sections`, in this order:
/// 1. `.client(hits:)` — "Already in your timeline"
/// 2. `.remote(platform: .mastodon, hits:)` — "From Mastodon"
/// 3. `.remote(platform: .bluesky, hits:)` — "From Bluesky"
@MainActor
public final class TimelineSearchViewModel: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var sections: [TimelineSearchSection] = []
    @Published public private(set) var phase: TimelineSearchPhase = .idle
    @Published public private(set) var query: String = ""

    // MARK: - Dependencies

    private let bufferProvider: () -> [Post]
    private let remoteDriver: TimelineSearchRemoteDriver
    /// The search scope. Currently `.unified` from the home timeline;
    /// `.pinned(...)` is honored when invoked from a pinned-timeline screen
    /// (see the pinnable-timelines plan).
    private let context: TimelineSearchContext
    private let debounceMs: Int

    // MARK: - In-Flight Work

    private var debounceTask: Task<Void, Never>?
    private var remoteTask: Task<Void, Never>?
    /// Monotonically increasing token to discard stale responses.
    private var generation: UInt64 = 0
    private var lastIssuedGeneration: UInt64 = 0

    // MARK: - Init

    public init(
        bufferProvider: @escaping () -> [Post],
        remoteDriver: TimelineSearchRemoteDriver,
        context: TimelineSearchContext,
        debounceMs: Int = 250
    ) {
        self.bufferProvider = bufferProvider
        self.remoteDriver = remoteDriver
        self.context = context
        self.debounceMs = debounceMs
    }

    // MARK: - Public API

    /// Update the query. Kicks debounce; eventually runs both layers.
    public func setQuery(_ newValue: String) {
        query = newValue
        debounceTask?.cancel()
        remoteTask?.cancel()

        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            sections = []
            phase = .idle
            return
        }

        phase = .debouncing
        generation &+= 1
        let gen = generation

        debounceTask = Task { [weak self] in
            guard let self else { return }
            if self.debounceMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(self.debounceMs) * 1_000_000)
            }
            if Task.isCancelled || gen != self.generation { return }
            await self.runLayered(trimmedQuery: trimmed, generation: gen)
        }
    }

    /// Test seam: wait until the current debounce + any in-flight remote task
    /// have settled. Not for production use.
    public func awaitSettled() async {
        if let debounce = debounceTask { _ = await debounce.value }
        if let remote = remoteTask { _ = await remote.value }
    }

    // MARK: - Internal

    private func runLayered(trimmedQuery: String, generation gen: UInt64) async {
        phase = .filtering
        let buffer = bufferProvider()
        let clientHits = TimelineBufferFilter.filter(buffer, query: trimmedQuery)
            .map { TimelineSearchHit(post: $0, source: .clientBuffer) }

        var nextSections: [TimelineSearchSection] = []
        if !clientHits.isEmpty {
            nextSections.append(.client(hits: clientHits))
        }
        sections = nextSections
        phase = .clientResultsOnly
        lastIssuedGeneration = gen

        remoteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let remoteHits = try await self.remoteDriver.search(
                    text: trimmedQuery, context: self.context
                )
                if Task.isCancelled || gen != self.generation { return }
                self.applyRemote(hits: remoteHits, generation: gen)
            } catch {
                if Task.isCancelled || gen != self.generation { return }
                self.applyRemoteFailure(generation: gen)
            }
        }
    }

    private func applyRemote(hits: [TimelineSearchHit], generation gen: UInt64) {
        guard gen == generation else { return }
        var grouped: [SocialPlatform: [TimelineSearchHit]] = [:]
        for hit in hits {
            if case .remote(let platform) = hit.source {
                grouped[platform, default: []].append(hit)
            }
        }
        var next = sections.filter {
            if case .client = $0 { return true } else { return false }
        }
        for platform in [SocialPlatform.mastodon, .bluesky] {
            if let h = grouped[platform], !h.isEmpty {
                next.append(.remote(platform: platform, hits: h))
            }
        }
        sections = next
        phase = .complete
    }

    private func applyRemoteFailure(generation gen: UInt64) {
        guard gen == generation else { return }
        phase = .clientResultsOnlyFailed
    }
}
