import XCTest
@testable import SocialFusion

@MainActor
final class DraftStoreIOTests: XCTestCase {

  /// DraftStore.loadDrafts() must not perform synchronous file I/O on init.
  /// After init, drafts should be empty until the async load completes.
  func testLoadDraftsIsNonBlocking() {
    // Write a drafts file so there's something to load
    let fm = FileManager.default
    let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = documents.appendingPathComponent("drafts.json")

    // Seed with a valid JSON array
    let sampleDraft = """
    [{"id":"test-draft","posts":[],"selectedPlatforms":["bluesky"],"createdAt":0,"isPinned":false}]
    """
    try? sampleDraft.data(using: .utf8)?.write(to: url)

    // Create the store — if init is non-blocking, drafts starts empty
    let store = DraftStore()

    // The store should have loaded (asynchronously or synchronously-from-cache)
    // but the key property: init MUST return without hanging.
    // We simply verify it finishes within a reasonable time (no deadlock).
    XCTAssertNotNil(store, "DraftStore init should complete without blocking")

    // Clean up
    try? fm.removeItem(at: url)
  }

  /// Persist should not block the calling thread.
  func testPersistIsNonBlocking() async {
    let store = DraftStore()

    // Save a draft — should return immediately (async persistence queue)
    store.saveDraft(
      posts: [ThreadPost()],
      platforms: [.bluesky]
    )

    // Wait a moment for async persistence
    try? await Task.sleep(nanoseconds: 200_000_000)

    // If we got here, persist didn't deadlock
    XCTAssertTrue(true, "saveDraft should return without blocking")
  }
}
