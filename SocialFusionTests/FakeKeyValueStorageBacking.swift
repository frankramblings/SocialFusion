import Foundation
@testable import SocialFusion

/// In-memory implementation of `KeyValueStorageBacking` for unit tests.
/// Lets tests simulate external changes by calling `simulateExternalChange(_:reason:)`.
public final class FakeKeyValueStorageBacking: KeyValueStorageBacking {
    private var storage: [String: Data] = [:]
    private var externalChangeHandler: (([String], ExternalChangeReason) -> Void)?

    public private(set) var synchronizeCallCount = 0
    public private(set) var setCallCount = 0

    public init() {}

    public func data(forKey key: String) -> Data? { storage[key] }

    public func set(_ data: Data?, forKey key: String) {
        setCallCount += 1
        if let data {
            storage[key] = data
        } else {
            storage.removeValue(forKey: key)
        }
    }

    public func removeObject(forKey key: String) { storage.removeValue(forKey: key) }

    public func allKeys() -> [String] { Array(storage.keys) }

    @discardableResult
    public func synchronize() -> Bool {
        synchronizeCallCount += 1
        return true
    }

    public func approximateByteCount() -> Int {
        storage.reduce(0) { $0 + $1.key.utf8.count + $1.value.count }
    }

    public func observeExternalChanges(
        _ handler: @escaping ([String], ExternalChangeReason) -> Void
    ) {
        externalChangeHandler = handler
    }

    /// Writes a value directly into storage and fires the external-change
    /// handler — simulating a push from another device.
    public func simulateExternalChange(
        key: String,
        data: Data?,
        reason: ExternalChangeReason = .serverChange
    ) {
        if let data {
            storage[key] = data
        } else {
            storage.removeValue(forKey: key)
        }
        externalChangeHandler?([key], reason)
    }
}
