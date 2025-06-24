import Foundation

/// YouTube URL extractor for native video playback
class YouTubeExtractor {
    static let shared = YouTubeExtractor()

    private init() {}

    /// Extract direct video URL from YouTube video ID
    func extractVideoURL(videoID: String) async throws -> URL {
        // Try multiple extraction methods
        let methods: [ExtractionMethod] = [
            .oEmbed,
            .videoInfo,
            .webPage,
        ]

        for method in methods {
            do {
                let url = try await extractURL(videoID: videoID, method: method)
                return url
            } catch {
                continue
            }
        }

        throw YouTubeExtractionError.allMethodsFailed
    }

    private func extractURL(videoID: String, method: ExtractionMethod) async throws -> URL {
        switch method {
        case .oEmbed:
            return try await extractFromOEmbed(videoID: videoID)
        case .videoInfo:
            return try await extractFromVideoInfo(videoID: videoID)
        case .webPage:
            return try await extractFromWebPage(videoID: videoID)
        }
    }

    // MARK: - Extraction Methods

    private func extractFromOEmbed(videoID: String) async throws -> URL {
        let oEmbedURL =
            "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoID)&format=json"

        guard let url = URL(string: oEmbedURL) else {
            throw YouTubeExtractionError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let thumbnailURL = json["thumbnail_url"] as? String
        else {
            throw YouTubeExtractionError.parsingFailed
        }

        // This method doesn't give us direct video URLs, but we can use it to validate the video exists
        // For now, we'll fall back to other methods
        throw YouTubeExtractionError.methodNotSupported
    }

    private func extractFromVideoInfo(videoID: String) async throws -> URL {
        let videoInfoURL = "https://www.youtube.com/get_video_info?video_id=\(videoID)"

        guard let url = URL(string: videoInfoURL) else {
            throw YouTubeExtractionError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw YouTubeExtractionError.parsingFailed
        }

        // Parse the response to extract video URLs
        // This is a simplified implementation - YouTube's API is complex
        if let extractedURL = parseVideoInfoResponse(responseString) {
            return extractedURL
        }

        throw YouTubeExtractionError.noValidStreams
    }

    private func extractFromWebPage(videoID: String) async throws -> URL {
        let webPageURL = "https://www.youtube.com/watch?v=\(videoID)"

        guard let url = URL(string: webPageURL) else {
            throw YouTubeExtractionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let html = String(data: data, encoding: .utf8) else {
            throw YouTubeExtractionError.parsingFailed
        }

        // Extract video URLs from the HTML page
        // This is a simplified implementation
        if let extractedURL = parseWebPageResponse(html) {
            return extractedURL
        }

        throw YouTubeExtractionError.noValidStreams
    }

    // MARK: - Response Parsers

    private func parseVideoInfoResponse(_ response: String) -> URL? {
        // This is a simplified parser - real implementation would be more complex
        var components = URLComponents()
        components.query = response

        guard let queryItems = components.queryItems else { return nil }

        // Look for streaming URLs in the response
        for item in queryItems {
            if item.name == "url_encoded_fmt_stream_map" || item.name == "adaptive_fmts" {
                if let value = item.value?.removingPercentEncoding {
                    return parseStreamMap(value)
                }
            }
        }

        return nil
    }

    private func parseWebPageResponse(_ html: String) -> URL? {
        // Look for video URLs in the HTML
        // This is a very simplified approach
        let patterns = [
            "\"url\":\"([^\"]+)\"",
            "'url':'([^']+)'",
            "\"hlsManifestUrl\":\"([^\"]+)\"",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: html.count)
                if let match = regex.firstMatch(in: html, options: [], range: range) {
                    let matchRange = match.range(at: 1)
                    if let swiftRange = Range(matchRange, in: html) {
                        let urlString = String(html[swiftRange])
                        if let url = URL(
                            string: urlString.replacingOccurrences(of: "\\u0026", with: "&"))
                        {
                            return url
                        }
                    }
                }
            }
        }

        return nil
    }

    private func parseStreamMap(_ streamMap: String) -> URL? {
        let streams = streamMap.components(separatedBy: ",")

        for stream in streams {
            let params = stream.components(separatedBy: "&")
            var streamURL: String?
            var quality: String?

            for param in params {
                let keyValue = param.components(separatedBy: "=")
                if keyValue.count == 2 {
                    let key = keyValue[0]
                    let value = keyValue[1].removingPercentEncoding ?? keyValue[1]

                    switch key {
                    case "url":
                        streamURL = value
                    case "quality":
                        quality = value
                    default:
                        break
                    }
                }
            }

            if let urlString = streamURL, let url = URL(string: urlString) {
                return url
            }
        }

        return nil
    }
}

// MARK: - Supporting Types

enum ExtractionMethod {
    case oEmbed
    case videoInfo
    case webPage
}

enum YouTubeExtractionError: Error, LocalizedError {
    case invalidURL
    case parsingFailed
    case noValidStreams
    case methodNotSupported
    case allMethodsFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid YouTube URL"
        case .parsingFailed:
            return "Failed to parse YouTube response"
        case .noValidStreams:
            return "No valid video streams found"
        case .methodNotSupported:
            return "Extraction method not supported"
        case .allMethodsFailed:
            return "All extraction methods failed"
        }
    }
}
