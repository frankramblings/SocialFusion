import Foundation
import os.log

/// Protocol defining the interface for Bluesky API interactions
public protocol BlueskyAPIClient {
    /// Fetches the timeline for a given account
    /// - Parameter account: The social account to fetch the timeline for
    /// - Returns: An array of posts
    func fetchTimeline(for account: SocialAccount) async throws -> [Post]

    /// Creates a new post on Bluesky
    /// - Parameters:
    ///   - content: The content of the post
    ///   - account: The account to post as
    ///   - replyTo: Optional ID of the post being replied to
    /// - Returns: The created post
    func createPost(content: String, account: SocialAccount, replyTo: String?) async throws -> Post

    /// Fetches a specific post by ID
    /// - Parameters:
    ///   - id: The ID of the post to fetch
    ///   - account: The account to fetch with
    /// - Returns: The requested post
    func fetchPost(id: String, account: SocialAccount) async throws -> Post
}

/// A client for interacting with the Bluesky API
public class BlueskyAPIClientImpl: BlueskyAPIClient {
    // MARK: - Properties

    private let logger = Logger(subsystem: "com.socialfusion", category: "BlueskyAPIClient")
    private let session: URLSession
    private let postNormalizer: PostNormalizer

    // MARK: - Initialization

    public init(session: URLSession = .shared, postNormalizer: PostNormalizer) {
        self.session = session
        self.postNormalizer = postNormalizer
    }

    // MARK: - Protocol Implementation

    public func fetchTimeline(for account: SocialAccount) async throws -> [Post] {
        let token = try await account.getValidAccessToken()
        let blueskyPosts = try await fetchTimeline(token: token)
        return try blueskyPosts.map { try postNormalizer.normalize($0) }
    }

    public func createPost(content: String, account: SocialAccount, replyTo: String?) async throws
        -> Post
    {
        let token = try await account.getValidAccessToken()
        let blueskyPost: BlueskyPost
        if let replyTo = replyTo {
            blueskyPost = try await replyToPost(id: replyTo, content: content, token: token)
        } else {
            blueskyPost = try await createPost(content: content, token: token)
        }
        return try postNormalizer.normalize(blueskyPost)
    }

    public func fetchPost(id: String, account: SocialAccount) async throws -> Post {
        let token = try await account.getValidAccessToken()
        let blueskyPost = try await fetchPost(id: id, token: token)
        return try postNormalizer.normalize(blueskyPost)
    }

    // MARK: - Private Methods

    private func makeURL(path: String) throws -> URL {
        guard let url = URL(string: "https://bsky.social/xrpc\(path)") else {
            throw BlueskyAPIClientError.invalidURL
        }
        return url
    }

    private func makeRequest(url: URL, method: String = "GET", token: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func createPost(content: String, token: String) async throws -> BlueskyPost {
        let url = try makeURL(path: "/com.atproto.repo.createRecord")
        var request = try makeRequest(url: url, method: "POST", token: token)

        let body: [String: Any] = [
            "collection": "app.bsky.feed.post",
            "repo": "did:plc:example",
            "record": [
                "text": content,
                "createdAt": ISO8601DateFormatter().string(from: Date()),
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlueskyAPIClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(BlueskyPost.self, from: data)
        case 401:
            throw BlueskyAPIClientError.unauthorized
        case 404:
            throw BlueskyAPIClientError.notFound
        default:
            throw BlueskyAPIClientError.serverError(httpResponse.statusCode)
        }
    }

    /// Fetch a post by its ID
    public func fetchPost(id: String, token: String) async throws -> BlueskyPost {
        let url = try makeURL(path: "/app.bsky.feed.getPost")
        var request = try makeRequest(url: url, token: token)

        // Add query parameters
        let queryItems = [URLQueryItem(name: "uri", value: id)]
        request.url = request.url?.appending(queryItems: queryItems)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlueskyAPIClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(BlueskyPostResponse.self, from: data)
            return result.post
        case 401:
            throw BlueskyAPIClientError.unauthorized
        case 404:
            throw BlueskyAPIClientError.notFound
        default:
            throw BlueskyAPIClientError.serverError(httpResponse.statusCode)
        }
    }

    /// Like a post
    public func likePost(id: String, token: String) async throws {
        let url = try makeURL(path: "/app.bsky.feed.like")
        var request = try makeRequest(url: url, method: "POST", token: token)

        // Add request body
        let body = [
            "subject": [
                "uri": id,
                "cid": "",  // This will be fetched from the post
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlueskyAPIClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return
        case 401:
            throw BlueskyAPIClientError.unauthorized
        case 404:
            throw BlueskyAPIClientError.notFound
        default:
            throw BlueskyAPIClientError.serverError(httpResponse.statusCode)
        }
    }

    /// Unlike a post
    public func unlikePost(id: String, token: String) async throws {
        let url = try makeURL(path: "/app.bsky.feed.unlike")
        var request = try makeRequest(url: url, method: "POST", token: token)

        // Add request body
        let body = [
            "subject": [
                "uri": id,
                "cid": "",  // This will be fetched from the post
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlueskyAPIClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return
        case 401:
            throw BlueskyAPIClientError.unauthorized
        case 404:
            throw BlueskyAPIClientError.notFound
        default:
            throw BlueskyAPIClientError.serverError(httpResponse.statusCode)
        }
    }

    /// Repost a post
    public func repostPost(id: String, token: String) async throws {
        let url = try makeURL(path: "/app.bsky.feed.repost")
        var request = try makeRequest(url: url, method: "POST", token: token)

        // Add request body
        let body = [
            "subject": [
                "uri": id,
                "cid": "",  // This will be fetched from the post
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlueskyAPIClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return
        case 401:
            throw BlueskyAPIClientError.unauthorized
        case 404:
            throw BlueskyAPIClientError.notFound
        default:
            throw BlueskyAPIClientError.serverError(httpResponse.statusCode)
        }
    }

    /// Unrepost a post
    public func unrepostPost(id: String, token: String) async throws {
        let url = try makeURL(path: "/app.bsky.feed.unrepost")
        var request = try makeRequest(url: url, method: "POST", token: token)

        // Add request body
        let body = [
            "subject": [
                "uri": id,
                "cid": "",  // This will be fetched from the post
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlueskyAPIClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return
        case 401:
            throw BlueskyAPIClientError.unauthorized
        case 404:
            throw BlueskyAPIClientError.notFound
        default:
            throw BlueskyAPIClientError.serverError(httpResponse.statusCode)
        }
    }

    /// Reply to a post
    public func replyToPost(id: String, content: String, token: String) async throws -> BlueskyPost
    {
        let url = try makeURL(path: "/app.bsky.feed.post")
        var request = try makeRequest(url: url, method: "POST", token: token)

        // Add request body
        let body: [String: Any] = [
            "text": content,
            "reply": [
                "parent": [
                    "uri": id,
                    "cid": "",  // This will be fetched from the post
                ],
                "root": [
                    "uri": id,
                    "cid": "",  // This will be fetched from the post
                ],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlueskyAPIClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(BlueskyPostResponse.self, from: data)
            return result.post
        case 401:
            throw BlueskyAPIClientError.unauthorized
        case 404:
            throw BlueskyAPIClientError.notFound
        default:
            throw BlueskyAPIClientError.serverError(httpResponse.statusCode)
        }
    }

    /// Fetch the timeline for an account
    public func fetchTimeline(token: String) async throws -> [BlueskyPost] {
        let url = try makeURL(path: "/app.bsky.feed.getTimeline")
        let request = try makeRequest(url: url, token: token)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlueskyAPIClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(BlueskyTimelineResponse.self, from: data)
            return result.feed.map { $0.post }
        case 401:
            throw BlueskyAPIClientError.unauthorized
        default:
            throw BlueskyAPIClientError.serverError(httpResponse.statusCode)
        }
    }
}

// MARK: - Response Types
private struct BlueskyPostResponse: Codable {
    let post: BlueskyPost
}

private struct BlueskyTimelineResponse: Codable {
    let feed: [BlueskyTimelineItem]
}

private struct BlueskyTimelineItem: Codable {
    let post: BlueskyPost
}

// MARK: - Errors
public enum BlueskyAPIClientError: Error {
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case serverError(Int)
}

// MARK: - Preview Helper
extension BlueskyAPIClient {
    static var preview: BlueskyAPIClient {
        BlueskyAPIClientImpl(postNormalizer: PostNormalizerImpl.shared)
    }
}

// MARK: - Models

/// Represents a Bluesky post
public struct APIBlueskyPost: Codable {
    public let uri: String
    public let cid: String
    public let author: BlueskyAuthor
    public let record: BlueskyRecord
    public let likeCount: Int
    public let repostCount: Int
    public let replyCount: Int
    public let indexedAt: String
    public let labels: [String]?
    public let embed: BlueskyEmbed?

    public struct BlueskyAuthor: Codable {
        public let did: String
        public let handle: String
        public let displayName: String?
        public let avatar: String?
    }

    public struct BlueskyRecord: Codable {
        public let text: String
        public let createdAt: String
        public let reply: BlueskyReply?
        public let embed: BlueskyEmbed?
    }

    public struct BlueskyReply: Codable {
        public let root: BlueskyReference
        public let parent: BlueskyReference
    }

    public struct BlueskyReference: Codable {
        public let uri: String
        public let cid: String
    }

    public struct BlueskyEmbed: Codable {
        public let type: String?
        public let images: [BlueskyImage]?
        public let record: BlueskyReference?
    }

    public struct BlueskyImage: Codable {
        public let alt: String
        public let fullsize: String
        public let thumb: String
    }
}
