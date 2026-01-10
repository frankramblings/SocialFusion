import Foundation

struct TimelineBufferSnapshot: Equatable {
    let bufferCount: Int
    let bufferEarliestTimestamp: Date?
    let bufferSources: Set<SocialPlatform>
}

@MainActor
final class TimelineBuffer {
    private var bufferedPosts: [Post] = []

    var snapshot: TimelineBufferSnapshot {
        TimelineBufferSnapshot(
            bufferCount: bufferedPosts.count,
            bufferEarliestTimestamp: bufferedPosts.map { $0.createdAt }.min(),
            bufferSources: Set(bufferedPosts.map { $0.platform })
        )
    }

    func append(incomingPosts: [Post], visiblePosts: [Post]) -> TimelineBufferSnapshot? {
        guard !incomingPosts.isEmpty else { return nil }
        let visibleIds = Set(visiblePosts.map { $0.stableId })
        let bufferedIds = Set(bufferedPosts.map { $0.stableId })
        let deduped = incomingPosts.filter { post in
            let id = post.stableId
            return !visibleIds.contains(id) && !bufferedIds.contains(id)
        }
        guard !deduped.isEmpty else { return nil }
        bufferedPosts.append(contentsOf: deduped)
        bufferedPosts.sort { $0.createdAt > $1.createdAt }
        return snapshot
    }

    func clear() -> TimelineBufferSnapshot {
        bufferedPosts.removeAll()
        return snapshot
    }

    func removeVisible(_ visiblePosts: [Post]) -> TimelineBufferSnapshot {
        guard !bufferedPosts.isEmpty else { return snapshot }
        let visibleIds = Set(visiblePosts.map { $0.stableId })
        bufferedPosts.removeAll { visibleIds.contains($0.stableId) }
        return snapshot
    }

    func drain() -> [Post] {
        let posts = bufferedPosts
        bufferedPosts.removeAll()
        return posts
    }
}

