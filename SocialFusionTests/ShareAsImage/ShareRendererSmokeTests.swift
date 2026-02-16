import XCTest
@testable import SocialFusion
import Darwin

/// Smoke tests for ShareImageRenderer - minimal rendering validation
/// These tests ensure the renderer doesn't crash and produces valid output
@MainActor
final class ShareRendererSmokeTests: XCTestCase {

    // MARK: - Basic Rendering Tests

    func testRenderPreviewProducesImage() async throws {
        // Given: A simple document
        let post = ShareAsImageTestHelpers.makePost(content: "Test post for rendering")
        var mapping: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig()

        let postRenderable = UnifiedAdapter.convertPost(post, hideUsernames: false, userMapping: &mapping)
        let document = ShareImageDocument(
            selectedPost: postRenderable,
            selectedCommentID: nil,
            ancestorChain: [],
            replySubtree: [],
            includePostDetails: true,
            hideUsernames: false,
            showWatermark: true,
            includeReplies: false
        )

        // When: Rendering preview
        let image = ShareImageRenderer.renderPreview(document: document)

        // Then: Should produce a valid image
        XCTAssertNotNil(image, "Renderer should produce an image")
        XCTAssertGreaterThan(image?.size.width ?? 0, 0, "Image width should be > 0")
        XCTAssertGreaterThan(image?.size.height ?? 0, 0, "Image height should be > 0")
    }

    func testRenderPreviewProducesPNGData() async throws {
        // Given: A simple document
        let post = ShareAsImageTestHelpers.makePost(content: "Test post for PNG")
        var mapping: [String: String] = [:]

        let postRenderable = UnifiedAdapter.convertPost(post, hideUsernames: false, userMapping: &mapping)
        let document = ShareImageDocument(
            selectedPost: postRenderable,
            selectedCommentID: nil,
            ancestorChain: [],
            replySubtree: [],
            includePostDetails: true,
            hideUsernames: false,
            showWatermark: true,
            includeReplies: false
        )

        // When: Rendering and encoding
        guard let image = ShareImageRenderer.renderPreview(document: document) else {
            XCTFail("Failed to render preview")
            return
        }
        let pngData = image.pngData()

        // Then: Should produce valid PNG data
        XCTAssertNotNil(pngData, "Should be able to encode as PNG")
        XCTAssertGreaterThan(pngData?.count ?? 0, 100, "PNG data should have meaningful size")
    }

    func testRenderExportProducesImage() async throws {
        // Given: A simple document
        let post = ShareAsImageTestHelpers.makePost(content: "Test post for export")
        var mapping: [String: String] = [:]

        let postRenderable = UnifiedAdapter.convertPost(post, hideUsernames: false, userMapping: &mapping)
        let document = ShareImageDocument(
            selectedPost: postRenderable,
            selectedCommentID: nil,
            ancestorChain: [],
            replySubtree: [],
            includePostDetails: true,
            hideUsernames: false,
            showWatermark: true,
            includeReplies: false
        )

        // When: Rendering export
        let image = try ShareImageRenderer.renderExport(document: document)

        // Then: Should produce a valid image
        XCTAssertGreaterThan(image.size.width, 0, "Export width should be > 0")
        XCTAssertGreaterThan(image.size.height, 0, "Export height should be > 0")

        // And: Export should be larger than preview
        // (Export is 1080px wide by default, preview is 640px)
        XCTAssertGreaterThan(image.size.width, 500, "Export should be high resolution")
    }

    // MARK: - Watermark Tests

    func testRenderWithWatermarkOn() async throws {
        // Given: Document with watermark enabled
        let post = ShareAsImageTestHelpers.makePost()
        var mapping: [String: String] = [:]

        let postRenderable = UnifiedAdapter.convertPost(post, hideUsernames: false, userMapping: &mapping)
        let document = ShareImageDocument(
            selectedPost: postRenderable,
            selectedCommentID: nil,
            ancestorChain: [],
            replySubtree: [],
            includePostDetails: true,
            hideUsernames: false,
            showWatermark: true, // Watermark ON
            includeReplies: false
        )

        // When: Rendering
        let image = ShareImageRenderer.renderPreview(document: document)

        // Then: Should succeed
        XCTAssertNotNil(image, "Should render with watermark on")
    }

    func testRenderWithWatermarkOff() async throws {
        // Given: Document with watermark disabled
        let post = ShareAsImageTestHelpers.makePost()
        var mapping: [String: String] = [:]

        let postRenderable = UnifiedAdapter.convertPost(post, hideUsernames: false, userMapping: &mapping)
        let document = ShareImageDocument(
            selectedPost: postRenderable,
            selectedCommentID: nil,
            ancestorChain: [],
            replySubtree: [],
            includePostDetails: true,
            hideUsernames: false,
            showWatermark: false, // Watermark OFF
            includeReplies: false
        )

        // When: Rendering
        let image = ShareImageRenderer.renderPreview(document: document)

        // Then: Should succeed
        XCTAssertNotNil(image, "Should render with watermark off")
    }

    // MARK: - Thread Rendering Tests

    func testRenderWithComments() async throws {
        // Given: Document with comments
        let (posts, selected, root, replies) = ShareAsImageTestHelpers.makeBranchingThread(replyCount: 3)
        let context = ThreadContext(mainPost: root, ancestors: [], descendants: replies)

        var mapping: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig(
            includeEarlier: false,
            includeLater: true
        )

        let document = ShareThreadRenderBuilder.buildDocument(
            from: selected,
            threadContext: context,
            config: config,
            userMapping: &mapping
        )

        // Verify we have comments
        XCTAssertGreaterThan(document.replySubtree.count, 0, "Should have comments to render")

        // When: Rendering
        let image = ShareImageRenderer.renderPreview(document: document)

        // Then: Should succeed
        XCTAssertNotNil(image, "Should render document with comments")
    }

    func testRenderWithAncestorChain() async throws {
        // Given: Document with ancestor chain
        let (posts, selected, root) = ShareAsImageTestHelpers.makeLinearChain(length: 4)
        let ancestors = posts.filter { $0.id != root.id && $0.id != selected.id }
        let context = ThreadContext(mainPost: root, ancestors: ancestors, descendants: [])

        var mapping: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig(
            includeEarlier: true, // Include ancestors
            includeLater: false
        )

        let document = ShareThreadRenderBuilder.buildDocument(
            from: selected,
            threadContext: context,
            config: config,
            userMapping: &mapping
        )

        // When: Rendering
        let image = ShareImageRenderer.renderPreview(document: document)

        // Then: Should succeed
        XCTAssertNotNil(image, "Should render document with ancestor chain")
    }

    // MARK: - Platform-Specific Tests

    func testRenderMastodonPost() async throws {
        // Given: A Mastodon post
        let post = ShareAsImageTestHelpers.makePost(platform: .mastodon)
        var mapping: [String: String] = [:]

        let postRenderable = UnifiedAdapter.convertPost(post, hideUsernames: false, userMapping: &mapping)
        let document = ShareImageDocument(
            selectedPost: postRenderable,
            selectedCommentID: nil,
            ancestorChain: [],
            replySubtree: [],
            includePostDetails: true,
            hideUsernames: false,
            showWatermark: true,
            includeReplies: false
        )

        // When: Rendering
        let image = ShareImageRenderer.renderPreview(document: document)

        // Then: Should succeed
        XCTAssertNotNil(image, "Should render Mastodon post")
    }

    func testRenderBlueskyPost() async throws {
        // Given: A Bluesky post
        let post = ShareAsImageTestHelpers.makePost(platform: .bluesky)
        var mapping: [String: String] = [:]

        let postRenderable = UnifiedAdapter.convertPost(post, hideUsernames: false, userMapping: &mapping)
        let document = ShareImageDocument(
            selectedPost: postRenderable,
            selectedCommentID: nil,
            ancestorChain: [],
            replySubtree: [],
            includePostDetails: true,
            hideUsernames: false,
            showWatermark: true,
            includeReplies: false
        )

        // When: Rendering
        let image = ShareImageRenderer.renderPreview(document: document)

        // Then: Should succeed
        XCTAssertNotNil(image, "Should render Bluesky post")
    }

    // MARK: - Anonymization Rendering Tests

    func testRenderWithAnonymization() async throws {
        // Given: Document with anonymization
        let post = ShareAsImageTestHelpers.makePost()
        var mapping: [String: String] = [:]

        let postRenderable = UnifiedAdapter.convertPost(post, hideUsernames: true, userMapping: &mapping)
        let document = ShareImageDocument(
            selectedPost: postRenderable,
            selectedCommentID: nil,
            ancestorChain: [],
            replySubtree: [],
            includePostDetails: true,
            hideUsernames: true, // Anonymized
            showWatermark: true,
            includeReplies: false
        )

        // When: Rendering
        let image = ShareImageRenderer.renderPreview(document: document)

        // Then: Should succeed
        XCTAssertNotNil(image, "Should render anonymized document")
    }

    func testShareAsImageViewModelInitialPreviewRendersQuickly() async throws {
        // Given: A simple post
        let post = ShareAsImageTestHelpers.makePost(content: "Preview speed test")

        // When: Opening share-as-image
        let viewModel = ShareAsImageViewModel(post: post, threadContext: nil, isReply: false)

        // Then: Initial preview should appear quickly
        let deadline = Date().addingTimeInterval(0.35)
        while viewModel.previewImage == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertNotNil(
            viewModel.previewImage,
            "Initial preview should render quickly, before media preloading fully completes."
        )
    }

    // MARK: - Save to File Tests

    func testSaveToTempFile() async throws {
        // Given: A rendered image
        let post = ShareAsImageTestHelpers.makePost()
        var mapping: [String: String] = [:]

        let postRenderable = UnifiedAdapter.convertPost(post, hideUsernames: false, userMapping: &mapping)
        let document = ShareImageDocument(
            selectedPost: postRenderable,
            selectedCommentID: nil,
            ancestorChain: [],
            replySubtree: [],
            includePostDetails: true,
            hideUsernames: false,
            showWatermark: true,
            includeReplies: false
        )

        guard let image = ShareImageRenderer.renderPreview(document: document) else {
            XCTFail("Failed to render image")
            return
        }

        // When: Saving to temp file
        let filename = "test-share-\(UUID().uuidString).png"
        let fileURL = try ShareImageRenderer.saveToTempFile(image, filename: filename)

        // Then: File should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "File should exist")

        // And: File should have content
        let data = try Data(contentsOf: fileURL)
        XCTAssertGreaterThan(data.count, 100, "File should have meaningful content")

        // Cleanup
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testSaveToTempFileWritesOpaqueImageData() throws {
        // Given: A rendered image
        let post = ShareAsImageTestHelpers.makePost(content: "Opaque output validation")
        var mapping: [String: String] = [:]

        let postRenderable = UnifiedAdapter.convertPost(post, hideUsernames: false, userMapping: &mapping)
        let document = ShareImageDocument(
            selectedPost: postRenderable,
            selectedCommentID: nil,
            ancestorChain: [],
            replySubtree: [],
            includePostDetails: true,
            hideUsernames: false,
            showWatermark: true,
            includeReplies: false
        )

        guard let image = ShareImageRenderer.renderPreview(document: document) else {
            XCTFail("Failed to render image")
            return
        }

        // When: Saving to temp file
        let filename = "test-share-opaque-\(UUID().uuidString).jpg"
        let fileURL = try ShareImageRenderer.saveToTempFile(image, filename: filename)
        let savedData = try Data(contentsOf: fileURL)
        let savedImage = try XCTUnwrap(UIImage(data: savedData))
        let cgImage = try XCTUnwrap(savedImage.cgImage)

        // Then: The encoded image should not contain an alpha channel
        XCTAssertFalse(hasAlphaChannel(cgImage.alphaInfo), "Saved share image should be encoded as opaque")

        // Cleanup
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testUpdateMemoryUsageInPreparationDoesNotLogRollbackWarning() {
        let manager = GradualMigrationManager.shared
        let originalPhase = manager.migrationPhase

        defer {
            manager.migrationPhase = originalPhase
        }

        manager.migrationPhase = .preparation

        let output = captureStandardOutput {
            manager.updateMemoryUsage(350.0)
        }

        XCTAssertFalse(
            output.contains("Cannot rollback from preparation"),
            "Auto-rollback checks should skip cleanly when there is no previous phase."
        )
    }

    // MARK: - Error Handling Tests

    func testRenderErrorForEncoding() async throws {
        // This test verifies the error types exist and are properly defined
        // We can't easily force an encoding failure, but we can verify the error type

        let error = ShareImageRenderer.RenderError.failedToEncode
        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(error.errorDescription?.contains("encode") == true, "Error should mention encoding")

        let renderError = ShareImageRenderer.RenderError.failedToRender
        XCTAssertNotNil(renderError.errorDescription, "Render error should have description")
    }

    // MARK: - Performance Baseline Tests

    func testRenderPerformanceBaseline() throws {
        // Given: A typical document
        let post = ShareAsImageTestHelpers.makePost(content: String(repeating: "Test content. ", count: 10))
        var mapping: [String: String] = [:]

        let postRenderable = UnifiedAdapter.convertPost(post, hideUsernames: false, userMapping: &mapping)
        let document = ShareImageDocument(
            selectedPost: postRenderable,
            selectedCommentID: nil,
            ancestorChain: [],
            replySubtree: [],
            includePostDetails: true,
            hideUsernames: false,
            showWatermark: true,
            includeReplies: false
        )

        // When: Measuring render time
        measure {
            let _ = ShareImageRenderer.renderPreview(document: document)
        }

        // Then: Test passes if measure completes without timeout
        // Performance baselines are established by the measure block
    }

    private func hasAlphaChannel(_ alphaInfo: CGImageAlphaInfo) -> Bool {
        switch alphaInfo {
        case .alphaOnly, .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return true
        }
    }

    private func captureStandardOutput(_ action: () -> Void) -> String {
        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)

        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        action()
        fflush(stdout)
        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
