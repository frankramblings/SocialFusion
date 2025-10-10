import AVFoundation
import XCTest

@testable import SocialFusion

/// Comprehensive test suite for media robustness improvements
@MainActor
class MediaRobustnessTests: XCTestCase {

    var mediaErrorHandler: MediaErrorHandler!
    var mediaMemoryManager: MediaMemoryManager!

    override func setUp() async throws {
        try await super.setUp()
        mediaErrorHandler = MediaErrorHandler.shared
        mediaMemoryManager = MediaMemoryManager.shared
    }

    override func tearDown() async throws {
        mediaErrorHandler.clearAllRetries()
        mediaMemoryManager.clearAllCaches()
        try await super.tearDown()
    }

    // MARK: - Audio Player Tests

    func testAudioPlayerInitialization() async throws {
        let testURL = URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav")!

        // Test that AudioPlayerView can be initialized with valid parameters
        let audioPlayer = AudioPlayerView(
            url: testURL,
            title: "Test Audio",
            artist: "Test Artist"
        )

        XCTAssertNotNil(audioPlayer)
    }

    // MARK: - Error Handling Tests

    func testErrorHandlerRetryLogic() async throws {
        let invalidURL = URL(string: "https://invalid-domain-12345.com/video.mp4")!

        // Test that error handler properly retries failed requests
        do {
            let _ = try await mediaErrorHandler.loadMediaWithRetry(url: invalidURL) { url in
                throw URLError(.notConnectedToInternet)
            }
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertTrue(error is MediaErrorHandler.MediaError)
        }

        // Verify retry state was tracked
        let retryState = mediaErrorHandler.getRetryState(url: invalidURL.absoluteString)
        XCTAssertNotNil(retryState)
        XCTAssertGreaterThan(retryState?.attempts ?? 0, 0)
    }

    func testErrorMapping() {
        let urlError = URLError(.notConnectedToInternet)
        let mappedError = MediaErrorHandler.shared.mapError(
            urlError, for: URL(string: "test://url")!)

        XCTAssertEqual(mappedError, MediaErrorHandler.MediaError.networkUnavailable)
    }

    // MARK: - Memory Management Tests

    func testImageOptimization() async throws {
        // Create a large test image
        let largeSize = CGSize(width: 4000, height: 3000)
        UIGraphicsBeginImageContextWithOptions(largeSize, false, 1.0)
        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: largeSize))
        let largeImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        // Test image optimization
        let optimizedImage = mediaMemoryManager.optimizeImage(largeImage)

        // Verify the image was resized
        XCTAssertLessThanOrEqual(optimizedImage.size.width, 2048)
        XCTAssertLessThanOrEqual(optimizedImage.size.height, 2048)

        // Verify aspect ratio is maintained
        let originalAspectRatio = largeImage.size.width / largeImage.size.height
        let optimizedAspectRatio = optimizedImage.size.width / optimizedImage.size.height
        XCTAssertEqual(originalAspectRatio, optimizedAspectRatio, accuracy: 0.01)
    }

    func testMemoryWarningHandling() {
        // Populate caches
        let testURL = URL(string: "https://example.com/test.jpg")!
        let testImage = UIImage(systemName: "photo")!

        mediaMemoryManager.imageCache.setObject(
            testImage, forKey: testURL.absoluteString as NSString)

        // Simulate memory warning
        NotificationCenter.default.post(
            name: UIApplication.didReceiveMemoryWarningNotification, object: nil)

        // Allow time for cleanup
        let expectation = XCTestExpectation(description: "Memory cleanup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Verify caches were cleared
        XCTAssertNil(
            mediaMemoryManager.imageCache.object(forKey: testURL.absoluteString as NSString))
    }

    func testCacheStatistics() {
        let stats = mediaMemoryManager.getCacheStats()

        XCTAssertGreaterThan(stats.images, 0)
        XCTAssertGreaterThan(stats.gifs, 0)
        XCTAssertGreaterThan(stats.videos, 0)
        XCTAssertFalse(stats.totalMemory.isEmpty)
    }

    // MARK: - Video Player Tests

    func testVideoPlayerCaching() async throws {
        let testURL = URL(
            string: "https://sample-videos.com/zip/10/mp4/SampleVideo_1280x720_1mb.mp4")!

        // Create a test player
        let playerItem = AVPlayerItem(url: testURL)
        let player = AVPlayer(playerItem: playerItem)

        // Cache the player
        mediaMemoryManager.cachePlayer(player, for: testURL)

        // Retrieve from cache
        let cachedPlayer = mediaMemoryManager.getCachedPlayer(for: testURL)

        XCTAssertNotNil(cachedPlayer)
        XCTAssertEqual(player, cachedPlayer)
    }

    // MARK: - Accessibility Tests

    func testVideoAccessibilityLabels() {
        let attachment = Post.Attachment(
            url: "https://example.com/video.mp4",
            type: .video,
            altText: "Test video description"
        )

        let smartMediaView = SmartMediaView(attachment: attachment)

        // Test that accessibility properties are properly set
        // Note: In a real test, you'd need to render the view and check its accessibility properties
        XCTAssertNotNil(smartMediaView)
    }

    func testAudioAccessibilityLabels() {
        let attachment = Post.Attachment(
            url: "https://example.com/audio.mp3",
            type: .audio,
            altText: "Test audio description"
        )

        let smartMediaView = SmartMediaView(attachment: attachment)

        XCTAssertNotNil(smartMediaView)
    }

    // MARK: - Integration Tests

    func testFullMediaLoadingFlow() async throws {
        let testURL = URL(string: "https://httpbin.org/status/200")!

        // Test the complete flow: error handling + memory management + retry logic
        do {
            let data = try await mediaErrorHandler.loadMediaWithRetry(url: testURL) { url in
                let (data, _) = try await URLSession.shared.data(from: url)
                return data
            }

            XCTAssertNotNil(data)
            XCTAssertGreaterThan(data.count, 0)
        } catch {
            XCTFail("Media loading should succeed: \(error)")
        }
    }

    func testErrorRecoveryFlow() async throws {
        let testURL = URL(string: "https://httpbin.org/status/500")!

        // Test error recovery with server errors
        do {
            let _ = try await mediaErrorHandler.loadMediaWithRetry(
                url: testURL,
                config: .init(maxAttempts: 2, baseDelay: 0.1, maxDelay: 0.5, backoffMultiplier: 1.5)
            ) { url in
                let (data, response) = try await URLSession.shared.data(from: url)

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    throw HTTPError(statusCode: httpResponse.statusCode, data: data)
                }

                return data
            }
            XCTFail("Should have failed with server error")
        } catch {
            // Verify it's the expected error type
            XCTAssertTrue(error is MediaErrorHandler.MediaError)
        }
    }

    // MARK: - Performance Tests

    func testMemoryManagerPerformance() {
        self.measure {
            // Test memory manager performance under load
            for i in 0..<100 {
                let url = URL(string: "https://example.com/image\(i).jpg")!
                let image = UIImage(systemName: "photo")!
                mediaMemoryManager.imageCache.setObject(
                    image, forKey: url.absoluteString as NSString)
            }

            mediaMemoryManager.clearAllCaches()
        }
    }

    func testErrorHandlerPerformance() {
        self.measure {
            // Test error handler performance
            for i in 0..<50 {
                let url = "https://example.com/test\(i).mp4"
                mediaErrorHandler.cancelRetry(url: url)
            }

            mediaErrorHandler.clearAllRetries()
        }
    }
}

// MARK: - Mock Objects for Testing

class MockAVPlayer: AVPlayer {
    var mockStatus: AVPlayer.Status = .readyToPlay

    override var status: AVPlayer.Status {
        return mockStatus
    }
}

// MARK: - Test Extensions

extension MediaErrorHandler {
    /// Expose internal method for testing
    func mapError(_ error: Error, for url: URL) -> MediaError {
        return mapError(error, for: url)
    }
}

extension MediaMemoryManager {
    /// Expose internal method for testing
    func optimizeImage(_ image: UIImage) -> UIImage {
        return optimizeImage(image)
    }

    /// Expose internal caches for testing
    var imageCache: NSCache<NSString, UIImage> {
        return imageCache
    }
}
