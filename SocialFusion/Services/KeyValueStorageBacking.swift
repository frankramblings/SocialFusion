import Foundation

/// Abstraction over a key-value blob store with external-change notifications.
///
/// Production binds to `NSUbiquitousKeyValueStore`; tests bind to an in-memory
/// fake. All access is expected to be on the main actor — `PositionSyncService`
/// enforces that contract.
public protocol KeyValueStorageBacking: AnyObject {
    /// Reads the raw Data for a key. Nil if the key is unset.
    func data(forKey key: String) -> Data?

    /// Writes raw Data for a key.
    func set(_ data: Data?, forKey key: String)

    /// Removes a key entirely (used when trimming to stay under the 1 MB cap).
    func removeObject(forKey key: String)

    /// Returns every currently known key in the store. Used for trimming.
    func allKeys() -> [String]

    /// Synchronously requests the store flush pending writes. Returns true on success.
    @discardableResult
    func synchronize() -> Bool

    /// Approximate total size of all stored values + keys in bytes. Used to
    /// detect when we're approaching the 1 MB KVS budget.
    func approximateByteCount() -> Int

    /// Registers a handler called when iCloud reports an externally-pushed
    /// change. Handler receives the array of changed keys (may be empty when
    /// the cause is `accountChange` or `quotaViolationChange`).
    func observeExternalChanges(
        _ handler: @escaping (_ changedKeys: [String], _ reason: ExternalChangeReason) -> Void
    )
}

/// Why an external-change notification fired. Mirrors
/// `NSUbiquitousKeyValueStore.ChangeReason` so callers don't have to import Foundation directly.
public enum ExternalChangeReason {
    case serverChange
    case initialSyncChange
    case quotaViolationChange
    case accountChange
    case unknown
}

/// Real backing wrapped around `NSUbiquitousKeyValueStore`.
// swiftlint:disable:next type_name
public final class iCloudKVSBacking: KeyValueStorageBacking {
    private let store: NSUbiquitousKeyValueStore
    private var observer: NSObjectProtocol?

    public init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func data(forKey key: String) -> Data? {
        store.data(forKey: key)
    }

    public func set(_ data: Data?, forKey key: String) {
        store.set(data, forKey: key)
    }

    public func removeObject(forKey key: String) {
        store.removeObject(forKey: key)
    }

    public func allKeys() -> [String] {
        Array(store.dictionaryRepresentation.keys)
    }

    @discardableResult
    public func synchronize() -> Bool {
        store.synchronize()
    }

    public func approximateByteCount() -> Int {
        var total = 0
        for (key, value) in store.dictionaryRepresentation {
            total += key.utf8.count
            if let d = value as? Data {
                total += d.count
            } else if let s = value as? String {
                total += s.utf8.count
            } else {
                // Rough estimate for primitives.
                total += 16
            }
        }
        return total
    }

    public func observeExternalChanges(
        _ handler: @escaping ([String], ExternalChangeReason) -> Void
    ) {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { note in
            let changedKeys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey]
                as? [String] ?? []
            let rawReason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let reason: ExternalChangeReason = {
                switch rawReason {
                case NSUbiquitousKeyValueStoreServerChange: return .serverChange
                case NSUbiquitousKeyValueStoreInitialSyncChange: return .initialSyncChange
                case NSUbiquitousKeyValueStoreQuotaViolationChange: return .quotaViolationChange
                case NSUbiquitousKeyValueStoreAccountChange: return .accountChange
                default: return .unknown
                }
            }()
            handler(changedKeys, reason)
        }
        // Per Apple docs: prompt the store to fetch on first observation.
        store.synchronize()
    }
}
