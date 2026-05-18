import Combine
import Foundation

@MainActor
public final class WatchedConversationStore: ObservableObject {
    @Published public private(set) var watched: [String: WatchedConversation] = [:]

    private let userDefaults: UserDefaults
    private let defaultsKey: String

    public init(
        userDefaults: UserDefaults = .standard,
        defaultsKey: String = "watched.conversations"
    ) {
        self.userDefaults = userDefaults
        self.defaultsKey = defaultsKey
        load()
    }

    public func watch(_ conv: WatchedConversation) {
        watched[conv.rootPostID] = conv
        persist()
    }

    public func unwatch(rootPostID: String) {
        if watched[rootPostID] != nil {
            watched.removeValue(forKey: rootPostID)
            persist()
        }
    }

    public func isWatching(rootPostID: String) -> Bool {
        watched[rootPostID] != nil
    }

    /// Returns all watched conversations, most recently watched first.
    public func allWatched() -> [WatchedConversation] {
        watched.values.sorted { $0.watchedAt > $1.watchedAt }
    }

    private func load() {
        guard let data = userDefaults.data(forKey: defaultsKey) else { return }
        guard let decoded = try? JSONDecoder().decode([String: WatchedConversation].self, from: data) else { return }
        self.watched = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(watched) else { return }
        userDefaults.set(data, forKey: defaultsKey)
    }
}
