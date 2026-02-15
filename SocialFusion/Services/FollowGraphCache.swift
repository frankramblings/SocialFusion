import Foundation

actor FollowGraphCache {
    private struct Entry {
        let users: Set<CanonicalUserID>
        let expiresAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let defaultTTL: TimeInterval

    init(defaultTTL: TimeInterval) {
        self.defaultTTL = defaultTTL
    }

    func value(for key: String, now: Date = Date()) -> Set<CanonicalUserID>? {
        guard let entry = entries[key] else { return nil }
        if entry.expiresAt <= now {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.users
    }

    func set(
        _ users: Set<CanonicalUserID>,
        for key: String,
        ttl: TimeInterval? = nil,
        now: Date = Date()
    ) {
        let expiry = now.addingTimeInterval(ttl ?? defaultTTL)
        entries[key] = Entry(users: users, expiresAt: expiry)
    }

    func invalidate(key: String) {
        entries.removeValue(forKey: key)
    }

    func invalidateAll() {
        entries.removeAll()
    }
}
