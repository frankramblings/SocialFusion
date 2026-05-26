import XCTest
@testable import SocialFusion

/// Integration test that exercises the real `NSUbiquitousKeyValueStore`.
/// Skipped when the simulator/device isn't signed into iCloud.
@MainActor
final class iCloudKVSBackingIntegrationTests: XCTestCase {
    private let testKey = "pos.test-acct.test-timeline"

    override func tearDown() async throws {
        NSUbiquitousKeyValueStore.default.removeObject(forKey: testKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        try await super.tearDown()
    }

    func testRealKVSRoundTrip() throws {
        try XCTSkipIf(
            !isiCloudAvailable(),
            "iCloud not available in this simulator. Sign in to test."
        )

        let backing = iCloudKVSBacking()
        let position = TimelinePosition(
            lastReadPostID: "integration-post",
            lastReadAt: Date(),
            scrollOffset: 42
        )
        let data = try JSONEncoder().encode(position)
        backing.set(data, forKey: testKey)
        XCTAssertTrue(backing.synchronize())

        let readback = try XCTUnwrap(backing.data(forKey: testKey))
        let decoded = try JSONDecoder().decode(TimelinePosition.self, from: readback)
        XCTAssertEqual(decoded, position)
    }

    func testByteCountReturnsPositiveAfterWrite() throws {
        try XCTSkipIf(!isiCloudAvailable(), "iCloud not available.")
        let backing = iCloudKVSBacking()
        backing.set(Data("hello".utf8), forKey: testKey)
        backing.synchronize()
        XCTAssertGreaterThan(backing.approximateByteCount(), 0)
    }

    private func isiCloudAvailable() -> Bool {
        // Probe: write, read back, clean up. If readback is nil, KVS isn't
        // functional (typically because no iCloud signin).
        let probeKey = "kvs-probe.\(UUID().uuidString)"
        NSUbiquitousKeyValueStore.default.set("ok", forKey: probeKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        let value = NSUbiquitousKeyValueStore.default.string(forKey: probeKey)
        NSUbiquitousKeyValueStore.default.removeObject(forKey: probeKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        return value == "ok"
    }
}
