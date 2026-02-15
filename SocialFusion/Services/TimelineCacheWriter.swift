import Foundation

actor TimelineCacheWriter {
    static let shared = TimelineCacheWriter()

    func saveTimeline(_ posts: [Post]) async {
        guard !posts.isEmpty else { return }
        if #available(iOS 17.0, *) {
            await TimelineSwiftDataStore.shared.saveTimeline(posts)
        } else {
            await PersistenceManager.shared.saveTimeline(posts)
        }
    }
}
