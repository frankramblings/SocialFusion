import AVFoundation
import Foundation
import ObjectiveC
import os.log

/// Handles authenticated video loading for Bluesky and Mastodon videos
class AuthenticatedVideoAssetLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let authToken: String
    private let originalURL: URL
    private let platform: SocialPlatform
    private let logger = Logger(
        subsystem: "com.socialfusion.app", category: "AuthenticatedVideoAssetLoader")

    init(authToken: String, originalURL: URL, platform: SocialPlatform) {
        self.authToken = authToken
        self.originalURL = originalURL
        self.platform = platform
        super.init()
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        // #region agent log
        let logData: [String: Any] = [
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "location": "AuthenticatedVideoAssetLoader.swift:20",
            "message": "resourceLoader_shouldWaitForLoading",
            "data": [
                "requestURL": loadingRequest.request.url?.absoluteString ?? "nil",
                "thread": Thread.isMainThread ? "main" : "background",
            ],
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "B",
        ]
        if let logJSON = try? JSONSerialization.data(withJSONObject: logData),
            let logString = String(data: logJSON, encoding: .utf8)
        {
            if let fileHandle = FileHandle(
                forWritingAtPath:
                    "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log")
            {
                fileHandle.seekToEndOfFile()
                fileHandle.write(("\n" + logString).data(using: .utf8) ?? Data())
                fileHandle.closeFile()
            } else {
                try? logString.write(
                    toFile: "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log",
                    atomically: false, encoding: .utf8)
            }
        }
        // #endregion

        // Extract the original URL from the custom scheme URL
        guard let requestURL = loadingRequest.request.url else {
            logger.error("❌ No request URL")
            loadingRequest.finishLoading(
                with: NSError(
                    domain: "AuthenticatedVideoAssetLoader", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return false
        }

        // Check if this is our custom scheme (optional check, but good for debugging)
        let isCustomScheme = requestURL.scheme == "authenticated-video"
        if isCustomScheme {
            logger.info(
                "🔐 Intercepted custom scheme request: \(requestURL.absoluteString, privacy: .public)"
            )
        }

        // Use the stored original URL for the actual request
        let actualURL = originalURL

        logger.info("🔐 Loading authenticated video: \(actualURL.absoluteString, privacy: .public)")

        // Check if this is a content information-only request (no data request)
        let isContentInfoOnly =
            loadingRequest.contentInformationRequest != nil && loadingRequest.dataRequest == nil
        if isContentInfoOnly {
            logger.info("🔐 Content information-only request - making HEAD request")
            handleContentInformationRequest(
                contentRequest: loadingRequest.contentInformationRequest!,
                loadingRequest: loadingRequest, url: actualURL)
            return true
        }

        // Create a new request with authentication headers
        var request = URLRequest(url: actualURL)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60.0  // Increase timeout for video loading

        // Capture range request details before async closure
        let requestedOffset: Int64
        let requestedLength: Int64
        if let dataRequest = loadingRequest.dataRequest {
            requestedOffset = dataRequest.requestedOffset
            requestedLength = Int64(dataRequest.requestedLength)

            if requestedLength != Int.max {
                // Range request - handle Int64 properly
                let endOffset = requestedOffset + requestedLength - 1
                let rangeHeader = "bytes=\(requestedOffset)-\(endOffset)"
                request.setValue(rangeHeader, forHTTPHeaderField: "Range")
                logger.info("🔐 Range request: \(rangeHeader, privacy: .public)")
            } else {
                logger.info("🔐 Full content request (no range)")
            }
        } else {
            requestedOffset = 0
            requestedLength = Int64.max
        }

        // Perform the authenticated request
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                // #region agent log
                let logData2: [String: Any] = [
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                    "location": "AuthenticatedVideoAssetLoader.swift:76",
                    "message": "loader_deallocated_during_request",
                    "data": [
                        "thread": Thread.isMainThread ? "main" : "background"
                    ],
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "A",
                ]
                if let logJSON2 = try? JSONSerialization.data(withJSONObject: logData2),
                    let logString2 = String(data: logJSON2, encoding: .utf8)
                {
                    if let fileHandle = FileHandle(
                        forWritingAtPath:
                            "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log")
                    {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(("\n" + logString2).data(using: .utf8) ?? Data())
                        fileHandle.closeFile()
                    } else {
                        try? logString2.write(
                            toFile:
                                "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log",
                            atomically: false, encoding: .utf8)
                    }
                }
                // #endregion
                let staticLogger = Logger(
                    subsystem: "com.socialfusion.app", category: "AuthenticatedVideoAssetLoader")
                staticLogger.error("❌ Loader deallocated during request")
                return
            }

            // Check if request was cancelled
            if loadingRequest.isCancelled {
                self.logger.warning("⚠️ Request was cancelled")
                return
            }

            if let error = error {
                self.logger.error(
                    "❌ Request failed: \(error.localizedDescription, privacy: .public)")
                loadingRequest.finishLoading(with: error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("❌ Invalid response type")
                loadingRequest.finishLoading(
                    with: NSError(
                        domain: "AuthenticatedVideoAssetLoader", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                return
            }

            let contentType = httpResponse.mimeType ?? "unknown"
            let contentLength =
                httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "unknown"
            self.logger.info(
                "🔐 HTTP \(httpResponse.statusCode) - Content-Type: \(contentType, privacy: .public), Content-Length: \(contentLength, privacy: .public)"
            )

            // Check for error status codes
            if httpResponse.statusCode >= 400 {
                let errorMsg =
                    "HTTP \(httpResponse.statusCode): \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"
                self.logger.error("❌ \(errorMsg, privacy: .public)")
                loadingRequest.finishLoading(
                    with: NSError(
                        domain: "AuthenticatedVideoAssetLoader", code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: errorMsg]))
                return
            }

            // Ensure we're on the main queue for AVAssetResourceLoader operations
            DispatchQueue.main.async {
                // Check again if cancelled
                if loadingRequest.isCancelled {
                    self.logger.warning("⚠️ Request was cancelled on main queue")
                    return
                }

                // CRITICAL: Set content information FIRST, before providing any data
                // AVFoundation needs this to recognize the video format
                // Only set if not already set (to avoid overwriting)
                if let contentRequest = loadingRequest.contentInformationRequest,
                    contentRequest.contentLength == 0
                {
                    // Determine content type - check for HLS playlists first
                    let contentType: String
                    let isHLSPlaylist =
                        self.originalURL.absoluteString.contains(".m3u8")
                        || self.originalURL.pathExtension == "m3u8"

                    if isHLSPlaylist {
                        // HLS playlists use application/vnd.apple.mpegurl or application/x-mpegURL
                        contentType = "application/vnd.apple.mpegurl"
                        self.logger.info(
                            "🔐 Detected HLS playlist - using content type: \(contentType, privacy: .public)"
                        )
                    } else if let mimeType = httpResponse.mimeType, mimeType.hasPrefix("video/") {
                        contentType = mimeType
                    } else if let mimeType = httpResponse.mimeType,
                        mimeType == "application/vnd.apple.mpegurl"
                            || mimeType == "application/x-mpegURL"
                    {
                        contentType = mimeType
                    } else {
                        // Default to video/mp4 for video URLs
                        contentType = "video/mp4"
                    }
                    contentRequest.contentType = contentType

                    // Get content length from response
                    // For 206 Partial Content, use Content-Range header to get full file size
                    // Format: "bytes 0-1/1234567" where 1234567 is the total size
                    var contentLength: Int64 = 0

                    if httpResponse.statusCode == 206 {
                        // Partial content - extract total size from Content-Range header
                        if let contentRange = httpResponse.value(
                            forHTTPHeaderField: "Content-Range")
                        {
                            // Parse "bytes 0-1/1234567" or "bytes */1234567"
                            let parts = contentRange.components(separatedBy: "/")
                            if parts.count == 2, let totalSize = Int64(parts[1]) {
                                contentLength = totalSize
                                self.logger.info(
                                    "🔐 Extracted full file size from Content-Range: \(contentLength) bytes"
                                )
                            }
                        }

                        // Fallback to Content-Length if Content-Range parsing failed
                        if contentLength == 0 {
                            if let contentLengthHeader = httpResponse.value(
                                forHTTPHeaderField: "Content-Length"),
                                let length = Int64(contentLengthHeader)
                            {
                                contentLength = length
                                self.logger.warning(
                                    "⚠️ Using partial Content-Length as fallback: \(contentLength) bytes"
                                )
                            }
                        }
                    } else {
                        // Full content (200 OK) - use Content-Length header
                        if let contentLengthHeader = httpResponse.value(
                            forHTTPHeaderField: "Content-Length"),
                            let length = Int64(contentLengthHeader)
                        {
                            contentLength = length
                        } else if let data = data {
                            contentLength = Int64(data.count)
                        }
                    }

                    contentRequest.contentLength = contentLength
                    contentRequest.isByteRangeAccessSupported =
                        httpResponse.statusCode == 206
                        || httpResponse.value(forHTTPHeaderField: "Accept-Ranges") == "bytes"

                    self.logger.info(
                        "🔐 Content info SET - Type: \(contentType, privacy: .public), Length: \(contentLength), ByteRangeSupported: \(contentRequest.isByteRangeAccessSupported)"
                    )

                    // CRITICAL: Content information must be set and processed by AVFoundation
                    // before we provide any data. Give it a moment to process.
                }

                // Provide data AFTER content information is set and processed
                // Use a small delay to ensure AVFoundation has processed the content info
                if let data = data, let dataRequest = loadingRequest.dataRequest {
                    // Check the actual requested offset from the data request
                    let actualRequestedOffset = dataRequest.requestedOffset
                    let actualRequestedLength = Int64(dataRequest.requestedLength)

                    self.logger.info(
                        "🔐 Data request - Offset: \(actualRequestedOffset), Length: \(actualRequestedLength), Data size: \(data.count)"
                    )

                    // Validate data before providing it
                    guard !data.isEmpty else {
                        self.logger.error("❌ Empty data received")
                        loadingRequest.finishLoading(
                            with: NSError(
                                domain: "AuthenticatedVideoAssetLoader", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Empty data"]))
                        return
                    }

                    // For offset 0, validate MP4 header (ftyp box should be at start)
                    if actualRequestedOffset == 0 && data.count >= 8 {
                        // MP4 files start with a 4-byte size, then "ftyp"
                        let typeBytes = data.subdata(in: 4..<8)
                        let typeString = String(data: typeBytes, encoding: .ascii) ?? ""

                        // Log first 16 bytes as hex for debugging
                        let hexString = data.prefix(16).map { String(format: "%02x", $0) }.joined(
                            separator: " ")
                        self.logger.info("🔍 First 16 bytes (hex): \(hexString, privacy: .public)")

                        if typeString == "ftyp" {
                            self.logger.info("✅ Valid MP4 header detected: ftyp")
                        } else {
                            self.logger.warning(
                                "⚠️ Data doesn't start with MP4 'ftyp' header. Type bytes: \(typeString, privacy: .public), First 4 bytes (hex): \(hexString.prefix(11), privacy: .public)"
                            )

                            // Check if it's a different video format
                            if typeString.hasPrefix("RIFF") {
                                self.logger.warning("⚠️ Detected AVI format (RIFF), not MP4")
                            } else if data.prefix(3) == Data([0x00, 0x00, 0x00]) {
                                self.logger.warning(
                                    "⚠️ Data starts with null bytes - might be corrupted or wrong format"
                                )
                            }
                        }
                    }

                    // Provide data - ensure it matches exactly what was requested
                    // AVFoundation's respond(with:) expects data starting at the requested offset
                    // Since we made a range request for the exact bytes, the data should match

                    // Verify data size matches request
                    let expectedSize =
                        actualRequestedLength == Int64.max ? data.count : Int(actualRequestedLength)
                    if data.count != expectedSize && actualRequestedLength != Int64.max {
                        self.logger.warning(
                            "⚠️ Data size mismatch: got \(data.count) bytes, expected \(expectedSize)"
                        )
                    }

                    // Provide the data - AVFoundation will process it
                    // Note: C++ exceptions from AVFoundation can't be caught, but valid MP4 data should work
                    dataRequest.respond(with: data)
                    self.logger.info(
                        "🔐 Provided \(data.count) bytes of data (requested: \(actualRequestedLength == Int64.max ? "all" : String(actualRequestedLength)))"
                    )
                } else {
                    self.logger.warning("⚠️ No data to provide")
                }

                loadingRequest.finishLoading()
                self.logger.info("✅ Request completed successfully")

                // #region agent log
                let logData3: [String: Any] = [
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                    "location": "AuthenticatedVideoAssetLoader.swift:244",
                    "message": "resourceLoader_request_completed",
                    "data": [
                        "dataSize": data?.count ?? 0,
                        "thread": Thread.isMainThread ? "main" : "background",
                    ],
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "B",
                ]
                if let logJSON3 = try? JSONSerialization.data(withJSONObject: logData3),
                    let logString3 = String(data: logJSON3, encoding: .utf8)
                {
                    if let fileHandle = FileHandle(
                        forWritingAtPath:
                            "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log")
                    {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(("\n" + logString3).data(using: .utf8) ?? Data())
                        fileHandle.closeFile()
                    } else {
                        try? logString3.write(
                            toFile:
                                "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log",
                            atomically: false, encoding: .utf8)
                    }
                }
                // #endregion
            }
        }

        task.resume()
        return true
    }

    /// Handle content information requests separately (for initial probe)
    /// Makes a HEAD request to get content information without downloading data
    private func handleContentInformationRequest(
        contentRequest: AVAssetResourceLoadingContentInformationRequest,
        loadingRequest: AVAssetResourceLoadingRequest, url: URL
    ) {
        logger.info("🔐 Making HEAD request for content information")

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30.0

        let task = URLSession.shared.dataTask(with: request) {
            [weak self] data, httpResponse, error in
            guard let self = self else { return }

            if loadingRequest.isCancelled {
                self.logger.warning("⚠️ Content information request was cancelled")
                return
            }

            if let error = error {
                self.logger.error(
                    "❌ HEAD request failed: \(error.localizedDescription, privacy: .public)")
                loadingRequest.finishLoading(with: error)
                return
            }

            guard let httpResponse = httpResponse as? HTTPURLResponse else {
                self.logger.error("❌ Invalid response from HEAD request")
                loadingRequest.finishLoading(
                    with: NSError(
                        domain: "AuthenticatedVideoAssetLoader", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                return
            }

            if httpResponse.statusCode >= 400 {
                self.logger.error("❌ HEAD request failed with status \(httpResponse.statusCode)")
                loadingRequest.finishLoading(
                    with: NSError(
                        domain: "AuthenticatedVideoAssetLoader", code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]))
                return
            }

            DispatchQueue.main.async {
                if loadingRequest.isCancelled {
                    self.logger.warning("⚠️ Content information request was cancelled on main queue")
                    return
                }

                // Set content type - check for HLS playlists first
                let contentType: String
                let isHLSPlaylist =
                    url.absoluteString.contains(".m3u8") || url.pathExtension == "m3u8"

                if isHLSPlaylist {
                    // HLS playlists use application/vnd.apple.mpegurl or application/x-mpegURL
                    contentType = "application/vnd.apple.mpegurl"
                    self.logger.info(
                        "🔐 HEAD: Detected HLS playlist - using content type: \(contentType, privacy: .public)"
                    )
                } else if let mimeType = httpResponse.mimeType, mimeType.hasPrefix("video/") {
                    contentType = mimeType
                } else if let mimeType = httpResponse.mimeType,
                    mimeType == "application/vnd.apple.mpegurl"
                        || mimeType == "application/x-mpegURL"
                {
                    contentType = mimeType
                } else {
                    contentType = "video/mp4"
                }
                contentRequest.contentType = contentType

                // Get content length
                var contentLength: Int64 = 0
                if let contentLengthHeader = httpResponse.value(
                    forHTTPHeaderField: "Content-Length"),
                    let length = Int64(contentLengthHeader)
                {
                    contentLength = length
                }

                contentRequest.contentLength = contentLength
                contentRequest.isByteRangeAccessSupported =
                    httpResponse.value(forHTTPHeaderField: "Accept-Ranges") == "bytes"

                self.logger.info(
                    "🔐 Content info set - Type: \(contentType, privacy: .public), Length: \(contentLength), ByteRangeSupported: \(contentRequest.isByteRangeAccessSupported)"
                )

                // Finish the content information request
                loadingRequest.finishLoading()
            }
        }

        task.resume()
    }

    /// Creates an authenticated AVURLAsset for Bluesky or Mastodon videos
    static func createAuthenticatedAsset(url: URL, authToken: String, platform: SocialPlatform)
        -> AVURLAsset
    {
        // Create a custom URL scheme to trigger the resource loader
        // The resource loader will intercept this and make the authenticated request
        // We preserve all URL components by reconstructing it with a custom scheme
        let logger = Logger(
            subsystem: "com.socialfusion.app", category: "AuthenticatedVideoAssetLoader")

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            logger.warning("⚠️ Failed to create URLComponents, using regular asset")
            return AVURLAsset(url: url)
        }

        // Replace the scheme with our custom scheme
        components.scheme = "authenticated-video"

        guard let customURL = components.url else {
            logger.warning("⚠️ Failed to create custom URL, using regular asset")
            return AVURLAsset(url: url)
        }

        logger.info(
            "🔐 Created custom URL: \(customURL.absoluteString, privacy: .public) from original: \(url.absoluteString, privacy: .public)"
        )

        let asset = AVURLAsset(url: customURL)

        // Set up resource loader with authentication
        let loader = AuthenticatedVideoAssetLoader(
            authToken: authToken, originalURL: url, platform: platform)
        asset.resourceLoader.setDelegate(loader, queue: DispatchQueue.main)

        // Retain the loader to prevent deallocation
        objc_setAssociatedObject(asset, "loader", loader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        return asset
    }
}

// MARK: - Helper Extensions

extension AuthenticatedVideoAssetLoader {
    /// Downloads an authenticated video to a temporary file
    /// This is a fallback when AVAssetResourceLoaderDelegate doesn't work reliably
    /// NOTE: This should NEVER be called for HLS playlists (.m3u8) - they must be streamed
    @MainActor
    static func downloadToTempFile(url: URL, authToken: String, platform: SocialPlatform)
        async throws -> URL
    {
        let logger = Logger(
            subsystem: "com.socialfusion.app", category: "AuthenticatedVideoAssetLoader")

        // CRITICAL: HLS playlists (.m3u8) should NEVER be downloaded - they must be streamed
        let isHLSPlaylist = url.absoluteString.contains(".m3u8") || url.pathExtension == "m3u8"
        if isHLSPlaylist {
            logger.error(
                "❌ downloadToTempFile called for HLS playlist (.m3u8) - this should not happen! HLS playlists must be streamed via resource loader."
            )
            throw NSError(
                domain: "AuthenticatedVideoAssetLoader", code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "HLS playlists (.m3u8) cannot be downloaded - they must be streamed"
                ])
        }

        logger.info(
            "📥 Downloading authenticated video to temp file: \(url.absoluteString, privacy: .public)"
        )

        // Create authenticated request
        var request = URLRequest(url: url)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120.0  // 2 minutes for large videos

        // Download data first, then write to temp file
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "AuthenticatedVideoAssetLoader", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "AuthenticatedVideoAssetLoader", code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
        }

        // Determine file extension from URL or Content-Type header
        let fileExtension: String
        let urlExtension = url.pathExtension
        if !urlExtension.isEmpty {
            fileExtension = urlExtension
        } else if let contentType = httpResponse.mimeType {
            // Map common MIME types to extensions
            if contentType.contains("mp4") {
                fileExtension = "mp4"
            } else if contentType.contains("webm") {
                fileExtension = "webm"
            } else if contentType.contains("quicktime") || contentType.contains("mov") {
                fileExtension = "mov"
            } else {
                fileExtension = "mp4"  // Default fallback
            }
        } else {
            fileExtension = "mp4"  // Default fallback
        }

        // Write to temporary file with appropriate extension
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let finalTempURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(
            fileExtension)

        try? fileManager.removeItem(at: finalTempURL)  // Remove if exists

        // Write data atomically and ensure it's synced to disk
        try data.write(to: finalTempURL, options: [.atomic, .completeFileProtection])

        // Ensure file is synced to disk before returning
        let fileHandle = try FileHandle(forWritingTo: finalTempURL)
        try fileHandle.synchronize()
        try fileHandle.close()

        // Verify file exists and has correct size
        guard fileManager.fileExists(atPath: finalTempURL.path) else {
            throw NSError(
                domain: "AuthenticatedVideoAssetLoader", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "File was not created"])
        }

        let attributes = try fileManager.attributesOfItem(atPath: finalTempURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        guard fileSize == data.count else {
            throw NSError(
                domain: "AuthenticatedVideoAssetLoader", code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "File size mismatch: expected \(data.count), got \(fileSize)"
                ])
        }

        logger.info(
            "✅ Downloaded to temp file: \(finalTempURL.lastPathComponent, privacy: .public) - \(httpResponse.statusCode), size: \(data.count) bytes, verified: \(fileSize) bytes"
        )

        return finalTempURL
    }

    /// Determines if a URL needs authentication (Bluesky or Mastodon)
    static func needsAuthentication(url: URL) -> (needsAuth: Bool, platform: SocialPlatform?) {
        let logger = Logger(
            subsystem: "com.socialfusion.app", category: "AuthenticatedVideoAssetLoader")

        guard let host = url.host?.lowercased() else {
            logger.debug("🔍 No host in URL: \(url.absoluteString, privacy: .public)")
            return (false, nil)
        }

        // Check for Bluesky domains
        if host.contains("bsky.app") || host.contains("bsky.social")
            || host.contains("cdn.bsky.app")
        {
            logger.info("🔍 Detected Bluesky URL: \(url.absoluteString, privacy: .public)")
            return (true, .bluesky)
        }

        // Check for Mastodon domains (common patterns)
        // Mastodon video URLs typically come from the instance domain
        let path = url.path.lowercased()
        if path.contains("/media/") || path.contains("/media_attachments/")
            || path.contains("/files/") || path.contains("/cache/media_attachments/")
            || path.contains("/system/cache/media_attachments/")
        {
            // This is likely a Mastodon media URL
            logger.info(
                "🔍 Detected Mastodon media URL: \(url.absoluteString, privacy: .public) (path: \(path, privacy: .public))"
            )
            return (true, .mastodon)
        }

        logger.debug("🔍 URL does not need authentication: \(url.absoluteString, privacy: .public)")
        return (false, nil)
    }

    /// Gets an account for the given platform
    @MainActor
    static func getAccountForPlatform(_ platform: SocialPlatform) async -> SocialAccount? {
        // Use AccountAccessor which tries multiple sources
        // AccountAccessor is @MainActor, so calling it will automatically ensure we're on the main actor
        return await AccountAccessor.shared.getAccountForPlatform(platform)
    }
}
