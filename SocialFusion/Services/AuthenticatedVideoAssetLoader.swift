import AVFoundation
import Foundation
import ObjectiveC
import os.log
import UIKit

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
            #if DEBUG
            print(logString)
            #endif
        }
        // #endregion

        // Extract the request URL
        guard let requestURL = loadingRequest.request.url else {
            logger.error("❌ No request URL")
            loadingRequest.finishLoading(
                with: NSError(
                    domain: "AuthenticatedVideoAssetLoader", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return false
        }

        // Check if this is our custom scheme or a standard URL that needs authentication
        let isCustomScheme = requestURL.scheme == "authenticated-video"
        let isStandardScheme = requestURL.scheme == "https" || requestURL.scheme == "http"

        // Check if this request needs authentication (Bluesky/Mastodon domains)
        let (needsAuth, _) = AuthenticatedVideoAssetLoader.needsAuthentication(url: requestURL)

        // Only handle requests that need authentication
        // For custom schemes, always handle (they're meant for us)
        // For standard schemes (https/http), handle if they need authentication
        // CRITICAL: For HLS with standard URLs, AVFoundation WILL call the resource loader
        // if we return true here. This is the correct approach to avoid -12881 errors.
        // Using standard URLs for HLS is recommended to avoid format description errors.
        if !isCustomScheme {
            if !isStandardScheme {
                // Not a standard scheme and not our custom scheme - let AVFoundation handle it
                return false
            }
            if !needsAuth {
                // Standard scheme but doesn't need authentication - let AVFoundation handle it
                return false
            }
            // Standard scheme that needs authentication - we handle it
            // AVFoundation will call us for all requests to this URL
        }

        if isCustomScheme {
            logger.info(
                "🔐 Intercepted custom scheme request: \(requestURL.absoluteString, privacy: .public)"
            )
        } else if needsAuth {
            logger.info(
                "🔐 Intercepted authenticated request: \(requestURL.absoluteString, privacy: .public)"
            )
        }

        // Reconstruct the actual URL from the request URL
        // For HLS, AVFoundation may request segment playlists (e.g., 360p/video.m3u8)
        // We need to preserve the path from the request URL, not always use originalURL
        let actualURL: URL
        if isCustomScheme {
            // Extract path, query, and fragment from the request URL
            // Reconstruct using the original URL's scheme and host, but preserve the request path
            guard let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
            else {
                logger.error("❌ Failed to parse request URL components")
                loadingRequest.finishLoading(
                    with: NSError(
                        domain: "AuthenticatedVideoAssetLoader", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid URL components"]))
                return false
            }

            // Use the original URL's scheme and host, but keep the request path
            guard
                var originalComponents = URLComponents(
                    url: originalURL, resolvingAgainstBaseURL: false)
            else {
                logger.error("❌ Failed to parse original URL components")
                loadingRequest.finishLoading(
                    with: NSError(
                        domain: "AuthenticatedVideoAssetLoader", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid original URL components"]))
                return false
            }

            // Preserve the path from the request (which may include segment paths like 360p/video.m3u8)
            // For HLS, paths might be relative (e.g., "360p/video.m3u8") or absolute (e.g., "/path/360p/video.m3u8")
            // If the path is relative and doesn't start with "/", resolve it relative to the original URL's directory
            var finalPath = components.path

            // Handle relative paths for HLS segments
            if !finalPath.isEmpty && !finalPath.hasPrefix("/") {
                // This is a relative path - resolve it against the original URL's directory
                let originalPath = originalComponents.path
                let originalDir = (originalPath as NSString).deletingLastPathComponent
                if originalDir.isEmpty || originalDir == "/" {
                    finalPath = "/" + finalPath
                } else {
                    finalPath = originalDir + "/" + finalPath
                }
                logger.info("🔐 Resolved relative HLS path: \(components.path) -> \(finalPath)")
            }

            originalComponents.path = finalPath
            originalComponents.query = components.query
            originalComponents.fragment = components.fragment

            guard let reconstructedURL = originalComponents.url else {
                logger.error(
                    "❌ Failed to reconstruct URL - path: \(finalPath), original: \(self.originalURL.absoluteString)"
                )
                loadingRequest.finishLoading(
                    with: NSError(
                        domain: "AuthenticatedVideoAssetLoader", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to reconstruct URL"]))
                return false
            }

            // Validate the reconstructed URL is valid
            guard reconstructedURL.scheme != nil && reconstructedURL.host != nil else {
                logger.error(
                    "❌ Reconstructed URL is invalid - scheme or host is nil: \(reconstructedURL.absoluteString)"
                )
                loadingRequest.finishLoading(
                    with: NSError(
                        domain: "AuthenticatedVideoAssetLoader", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid reconstructed URL"]))
                return false
            }

            actualURL = reconstructedURL
        } else {
            // Standard scheme (https/http) that needs authentication - use as-is
            actualURL = requestURL
        }

        logger.info("🔐 Loading authenticated video: \(actualURL.absoluteString, privacy: .public)")

        // Check if this is a content information-only request (no data request)
        // CRITICAL: Handle content information requests immediately to prevent AVFoundation crashes
        // AVFoundation needs content information before it can initialize the player item
        if let contentRequest = loadingRequest.contentInformationRequest {
            let isHLSPlaylist = actualURL.absoluteString.contains(".m3u8") || actualURL.pathExtension == "m3u8"
            let isHLSSegment = actualURL.absoluteString.contains(".ts") || actualURL.pathExtension == "ts"
            
            if isHLSPlaylist || isHLSSegment {
                logger.info("🔐 HLS content info request - providing synchronously")
                contentRequest.contentType = isHLSPlaylist ? "application/vnd.apple.mpegurl" : "video/mp2t"
                contentRequest.isByteRangeAccessSupported = true
                // We don't know the exact length yet, but for HLS it often doesn't matter or will be updated
                
                if loadingRequest.dataRequest == nil {
                    loadingRequest.finishLoading()
                    return true
                }
            }
        }

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
        
        // CRITICAL: Set proper Accept headers based on content type
        // Many CDNs (including Bluesky's) require proper Accept headers
        let isHLSPlaylist = actualURL.absoluteString.contains(".m3u8") || actualURL.pathExtension == "m3u8"
        let isHLSSegment = actualURL.absoluteString.contains(".ts") || actualURL.pathExtension == "ts"
        
        if isHLSPlaylist {
            // HLS playlists need specific Accept header
            request.setValue("application/vnd.apple.mpegurl, application/x-mpegURL, */*", forHTTPHeaderField: "Accept")
        } else if isHLSSegment {
            // HLS segments are MPEG Transport Stream
            request.setValue("video/mp2t, video/*, */*", forHTTPHeaderField: "Accept")
        } else {
            // Regular video content
            request.setValue("video/*, */*", forHTTPHeaderField: "Accept")
        }
        
        // CRITICAL: Add User-Agent header - many CDNs require this and block requests without it
        // Use a standard iOS User-Agent format similar to what AVFoundation would send
        let userAgent = "SocialFusion/1.0 (iPhone; iOS \(UIDevice.current.systemVersion)) AppleWebKit/605.1.15"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
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
        // Capture actualURL for use in the closure
        let capturedActualURL = actualURL
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
                    #if DEBUG
                    print(logString2)
                    #endif
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

            // CRITICAL: All AVFoundation operations (including finishLoading) must happen on main thread
            // to prevent "Modifying properties of a view's layer off the main thread" crashes
            DispatchQueue.main.async {
                if let error = error {
                    // Enhanced error logging for network failures
                    let urlError = error as? URLError
                    self.logger.error(
                        "❌ Request failed: \(error.localizedDescription, privacy: .public) - URL: \(capturedActualURL.absoluteString, privacy: .public)"
                    )
                    if let urlError = urlError {
                        self.logger.error(
                            "❌ URLError code: \(urlError.code.rawValue), domain: \(urlError.localizedDescription, privacy: .public)"
                        )
                        // Check for common network issues
                        switch urlError.code {
                        case .notConnectedToInternet:
                            self.logger.error("❌ No internet connection")
                        case .timedOut:
                            self.logger.error("❌ Request timed out - CDN might be slow or blocking")
                        case .cannotFindHost:
                            self.logger.error("❌ Cannot find host - DNS or network issue")
                        case .cannotConnectToHost:
                            self.logger.error("❌ Cannot connect to host - network or firewall issue")
                        default:
                            break
                        }
                    }
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
                    
                    // Log additional diagnostic information
                    let requestHeaders = request.allHTTPHeaderFields ?? [:]
                    let responseHeaders = httpResponse.allHeaderFields
                    self.logger.error(
                        "❌ \(errorMsg, privacy: .public) - URL: \(capturedActualURL.absoluteString, privacy: .public)"
                    )
                    self.logger.error(
                        "❌ Request headers: \(requestHeaders.keys.joined(separator: ", "), privacy: .public)"
                    )
                    self.logger.error(
                        "❌ Response headers: \(String(describing: responseHeaders.keys), privacy: .public)"
                    )
                    
                    // Check for common CDN rejection reasons
                    if httpResponse.statusCode == 403 {
                        self.logger.error(
                            "❌ 403 Forbidden - This might indicate missing User-Agent or authentication issues"
                        )
                    } else if httpResponse.statusCode == 401 {
                        self.logger.error(
                            "❌ 401 Unauthorized - Authentication token might be invalid or expired"
                        )
                    }
                    
                    loadingRequest.finishLoading(
                        with: NSError(
                            domain: "AuthenticatedVideoAssetLoader", code: httpResponse.statusCode,
                            userInfo: [
                                NSLocalizedDescriptionKey: errorMsg,
                                NSURLErrorKey: capturedActualURL
                            ]))
                    return
                }

                // Ensure we're on the main queue for AVAssetResourceLoader operations
                // Check again if cancelled
                if loadingRequest.isCancelled {
                    self.logger.warning("⚠️ Request was cancelled on main queue")
                    return
                }

                // CRITICAL: Set content information FIRST, before providing any data
                // AVFoundation needs this to recognize the video format
                // Only set if not already set (to avoid overwriting)
                if let contentRequest = loadingRequest.contentInformationRequest,
                    contentRequest.contentLength == 0 && contentRequest.contentType == nil
                {
                    // Determine content type - check for HLS playlists and segments first
                    let contentType: String
                    let isHLSPlaylist =
                        capturedActualURL.absoluteString.contains(".m3u8")
                        || capturedActualURL.pathExtension == "m3u8"
                    let isHLSSegment =
                        capturedActualURL.absoluteString.contains(".ts")
                        || capturedActualURL.pathExtension == "ts"

                    if isHLSPlaylist {
                        // HLS playlists use application/vnd.apple.mpegurl or application/x-mpegURL
                        contentType = "application/vnd.apple.mpegurl"
                        self.logger.info(
                            "🔐 Detected HLS playlist - using content type: \(contentType, privacy: .public)"
                        )
                    } else if isHLSSegment {
                        // HLS video segments (.ts files) are MPEG Transport Stream format
                        // AVFoundation requires the correct content type for HLS segments
                        // MPEG Transport Stream uses video/mp2t (RFC 3555)
                        contentType = "video/mp2t"
                        self.logger.info(
                            "🔐 Detected HLS segment (.ts) - using content type: \(contentType, privacy: .public)"
                        )
                    } else if let mimeType = httpResponse.mimeType, mimeType.hasPrefix("video/") {
                        contentType = mimeType
                    } else if let mimeType = httpResponse.mimeType,
                        mimeType == "application/vnd.apple.mpegurl"
                            || mimeType == "application/x-mpegURL"
                    {
                        contentType = mimeType
                    } else {
                        // Default to video/mp4 for video URLs (but not for HLS segments)
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

                    // CRITICAL FIX: For HLS segments, always claim byte range support
                    // HLS (HTTP Live Streaming) is designed to work with byte ranges, and AVFoundation
                    // expects this. Even when AVFoundation requests all data at once, claiming byte range
                    // support is correct because HLS segments are served with range support.
                    // The -12881 error was occurring because AVFoundation expected range support but
                    // we were claiming false when it requested all data.
                    let requestedLength = loadingRequest.dataRequest?.requestedLength ?? Int.max
                    let serverSupportsRanges =
                        httpResponse.statusCode == 206
                        || httpResponse.value(forHTTPHeaderField: "Accept-Ranges") == "bytes"

                    if isHLSSegment {
                        // For HLS segments, ALWAYS claim byte range support - HLS is designed for ranges
                        // Even if AVFoundation requests all data, the server supports ranges and
                        // AVFoundation expects this capability for HLS content.
                        contentRequest.isByteRangeAccessSupported = true
                        self.logger.info(
                            "🔐 HLS segment - byte range support: true (HLS always supports ranges, requested length: \(requestedLength == Int.max ? "all" : String(requestedLength)), server supports: \(serverSupportsRanges))"
                        )
                    } else {
                        // For non-HLS content, use server support as indicator
                        contentRequest.isByteRangeAccessSupported = serverSupportsRanges
                    }

                    self.logger.info(
                        "🔐 Content info SET - Type: \(contentType, privacy: .public), Length: \(contentLength), ByteRangeSupported: \(contentRequest.isByteRangeAccessSupported)"
                    )

                    // CRITICAL: Content information is set synchronously and immediately
                    // No delays needed - successful apps provide data immediately after content info
                    // The format description will be available because we load asset properties first
                }

                // Provide data AFTER content information is set and processed
                // For HLS playlists, we might need to process the content to ensure segment URLs are handled correctly
                if let data = data, loadingRequest.dataRequest != nil {
                    let isHLSPlaylist =
                        capturedActualURL.absoluteString.contains(".m3u8")
                        || capturedActualURL.pathExtension == "m3u8"

                    if isHLSPlaylist {
                        // For HLS playlists, provide the data as-is
                        // AVFoundation will parse the playlist and request segments
                        // Segment requests will also go through the resource loader if they need authentication
                        self.provideDataForRequest(loadingRequest: loadingRequest, data: data)
                    } else {
                        // For non-HLS content, provide data immediately
                        self.provideDataForRequest(loadingRequest: loadingRequest, data: data)
                    }
                } else {
                    // If there's no data or no data request, just finish
                    loadingRequest.finishLoading()
                    if data == nil {
                        self.logger.warning("⚠️ No data received")
                    } else {
                        self.logger.info("✅ Content information set, no data request")
                    }
                }
            }
        }

        task.resume()
        return true
    }

    /// Helper method to provide data for a loading request
    /// Extracted to avoid code duplication and ensure consistent handling
    /// CRITICAL: All AVFoundation operations must happen on main thread
    private func provideDataForRequest(loadingRequest: AVAssetResourceLoadingRequest, data: Data) {
        // CRITICAL: Ensure we're on the main thread for all AVFoundation operations
        // This prevents "Modifying properties of a view's layer off the main thread" crashes
        if !Thread.isMainThread {
            logger.warning("⚠️ provideDataForRequest called off main thread - dispatching to main")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.provideDataForRequest(loadingRequest: loadingRequest, data: data)
            }
            return
        }

        guard let dataRequest = loadingRequest.dataRequest else {
            logger.warning("⚠️ No data request to provide data for")
            loadingRequest.finishLoading()
            return
        }

        // Check again if cancelled
        if loadingRequest.isCancelled {
            logger.warning("⚠️ Request was cancelled before providing data")
            return
        }

        // Check the actual requested offset from the data request
        let actualRequestedOffset = dataRequest.requestedOffset
        let actualRequestedLength = Int64(dataRequest.requestedLength)

        logger.info(
            "🔐 Data request - Offset: \(actualRequestedOffset), Length: \(actualRequestedLength), Data size: \(data.count)"
        )

        // Validate data before providing it
        guard !data.isEmpty else {
            logger.error("❌ Empty data received")
            loadingRequest.finishLoading(
                with: NSError(
                    domain: "AuthenticatedVideoAssetLoader", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Empty data"]))
            return
        }

        // Validate data format based on content type
        // Skip validation for HLS segments (.ts files) - they're MPEG-TS, not MP4
        let isHLSSegment =
            loadingRequest.request.url?.absoluteString.contains(".ts") == true
            || loadingRequest.request.url?.pathExtension == "ts"

        if !isHLSSegment && actualRequestedOffset == 0 && data.count >= 8 {
            // MP4 files start with a 4-byte size, then "ftyp"
            let typeBytes = data.subdata(in: 4..<8)
            let typeString = String(data: typeBytes, encoding: .ascii) ?? ""

            // Log first 16 bytes as hex for debugging
            let hexString = data.prefix(16).map { String(format: "%02x", $0) }.joined(
                separator: " ")
            logger.info("🔍 First 16 bytes (hex): \(hexString, privacy: .public)")

            if typeString == "ftyp" {
                logger.info("✅ Valid MP4 header detected: ftyp")
            } else {
                logger.warning(
                    "⚠️ Data doesn't start with MP4 'ftyp' header. Type bytes: \(typeString, privacy: .public), First 4 bytes (hex): \(hexString.prefix(11), privacy: .public)"
                )

                // Check if it's a different video format
                if typeString.hasPrefix("RIFF") {
                    logger.warning("⚠️ Detected AVI format (RIFF), not MP4")
                } else if data.prefix(3) == Data([0x00, 0x00, 0x00]) {
                    logger.warning(
                        "⚠️ Data starts with null bytes - might be corrupted or wrong format"
                    )
                }
            }
        } else if isHLSSegment && actualRequestedOffset == 0 && data.count >= 1 {
            // MPEG-TS files start with sync byte 0x47
            let syncByte = data[0]
            if syncByte == 0x47 {
                logger.info("✅ Valid MPEG-TS sync byte detected: 0x47")
            } else {
                logger.warning(
                    "⚠️ MPEG-TS segment doesn't start with sync byte 0x47. First byte: 0x\(String(format: "%02x", syncByte), privacy: .public)"
                )
            }
        }

        // Provide data - ensure it matches exactly what was requested
        // AVFoundation's respond(with:) expects data starting at the requested offset
        // Since we made a range request for the exact bytes, the data should match

        // Verify data size matches request
        let expectedSize =
            actualRequestedLength == Int64.max ? data.count : Int(actualRequestedLength)
        if data.count != expectedSize && actualRequestedLength != Int64.max {
            logger.warning(
                "⚠️ Data size mismatch: got \(data.count) bytes, expected \(expectedSize)"
            )
        }

        // Provide the data - AVFoundation will process it
        // Note: C++ exceptions from AVFoundation can't be caught, but valid MP4 data should work
        // CRITICAL: Check again if cancelled before responding (race condition protection)
        if loadingRequest.isCancelled {
            logger.warning("⚠️ Request was cancelled right before providing data")
            return
        }

        // Provide data - respond(with:) doesn't throw, but we check cancellation for safety
        dataRequest.respond(with: data)
        logger.info(
            "🔐 Provided \(data.count) bytes of data (requested: \(actualRequestedLength == Int64.max ? "all" : String(actualRequestedLength)))"
        )

        // Finish loading immediately after providing data
        // No delays needed - successful apps finish immediately after providing data
        // CRITICAL: Final check before finishing to prevent crashes
        if loadingRequest.isCancelled {
            logger.warning("⚠️ Request was cancelled right before finishing")
            return
        }

        // Finish loading immediately - content info was set synchronously and data is provided
        loadingRequest.finishLoading()
        logger.info("✅ Request completed successfully")

        // #region agent log
        let logData3: [String: Any] = [
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "location": "AuthenticatedVideoAssetLoader.swift:244",
            "message": "resourceLoader_request_completed",
            "data": [
                "dataSize": data.count,
                "thread": Thread.isMainThread ? "main" : "background",
            ],
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "B",
        ]
        if let logJSON3 = try? JSONSerialization.data(withJSONObject: logData3),
            let logString3 = String(data: logJSON3, encoding: .utf8)
        {
            #if DEBUG
            print(logString3)
            #endif
        }
        // #endregion
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
        
        // CRITICAL: Set proper Accept headers based on content type
        let isHLSPlaylist = url.absoluteString.contains(".m3u8") || url.pathExtension == "m3u8"
        let isHLSSegment = url.absoluteString.contains(".ts") || url.pathExtension == "ts"
        
        if isHLSPlaylist {
            request.setValue("application/vnd.apple.mpegurl, application/x-mpegURL, */*", forHTTPHeaderField: "Accept")
        } else if isHLSSegment {
            request.setValue("video/mp2t, video/*, */*", forHTTPHeaderField: "Accept")
        } else {
            request.setValue("video/*, */*", forHTTPHeaderField: "Accept")
        }
        
        // CRITICAL: Add User-Agent header for HEAD requests too
        let userAgent = "SocialFusion/1.0 (iPhone; iOS \(UIDevice.current.systemVersion)) AppleWebKit/605.1.15"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        request.timeoutInterval = 30.0

        let task = URLSession.shared.dataTask(with: request) {
            [weak self] data, httpResponse, error in
            guard let self = self else { return }

            // CRITICAL: All AVFoundation operations (including finishLoading) must happen on main thread
            // to prevent "Modifying properties of a view's layer off the main thread" crashes
            DispatchQueue.main.async {
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
                    self.logger.error(
                        "❌ HEAD request failed with status \(httpResponse.statusCode)")
                    loadingRequest.finishLoading(
                        with: NSError(
                            domain: "AuthenticatedVideoAssetLoader", code: httpResponse.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]
                        ))
                    return
                }

                // Set content type - check for HLS playlists and segments first
                let contentType: String
                let isHLSPlaylist =
                    url.absoluteString.contains(".m3u8") || url.pathExtension == "m3u8"
                let isHLSSegment =
                    url.absoluteString.contains(".ts") || url.pathExtension == "ts"

                if isHLSPlaylist {
                    // HLS playlists use application/vnd.apple.mpegurl or application/x-mpegURL
                    contentType = "application/vnd.apple.mpegurl"
                    self.logger.info(
                        "🔐 HEAD: Detected HLS playlist - using content type: \(contentType, privacy: .public)"
                    )
                } else if isHLSSegment {
                    // HLS video segments (.ts files) are MPEG Transport Stream format
                    contentType = "video/mp2t"
                    self.logger.info(
                        "🔐 HEAD: Detected HLS segment (.ts) - using content type: \(contentType, privacy: .public)"
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

                // CRITICAL FIX: For HEAD requests, claim byte range support for HLS segments
                // HLS is designed to work with byte ranges, so we should always claim support.
                // The actual data request will confirm this, but claiming it early is correct.
                if isHLSSegment {
                    // For HLS segments, always claim byte range support - HLS is designed for ranges
                    contentRequest.isByteRangeAccessSupported = true
                    self.logger.info(
                        "🔐 HEAD: HLS segment - byte range support: true (HLS always supports ranges)"
                    )
                } else {
                    // For non-HLS content, use server support as indicator
                    contentRequest.isByteRangeAccessSupported =
                        httpResponse.value(forHTTPHeaderField: "Accept-Ranges") == "bytes"
                }

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
