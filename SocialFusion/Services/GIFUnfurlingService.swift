import Foundation
import UIKit

final class GIFUnfurlingService {
    static let shared = GIFUnfurlingService()
    private init() {}

    struct UnfurledGIF {
        let data: Data
        let contentType: String
    }

    enum UnfurlError: Error {
        case disabled
        case invalidURL
        case fetchFailed
    }

    func unfurl(url: URL) async throws -> UnfurledGIF {
        guard FeatureFlags.enableGIFUnfurling else { throw UnfurlError.disabled }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UnfurlError.fetchFailed
        }
        let contentType =
            (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "image/gif"
        return UnfurledGIF(data: data, contentType: contentType)
    }
}

