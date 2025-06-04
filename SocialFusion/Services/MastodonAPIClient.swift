import Foundation
import os.log

/// Protocol defining the interface for Mastodon API interactions
public protocol MastodonAPIClient {
    /// Fetches the timeline for a given account
    /// - Parameter account: The social account to fetch the timeline for
    /// - Returns: An array of posts
    func fetchTimeline(for account: SocialAccount) async throws -> [Post]

    /// Posts a new status to Mastodon
    /// - Parameters:
    ///   - content: The content of the post
    ///   - account: The account to post as
    ///   - replyTo: Optional ID of the post being replied to
    /// - Returns: The created post
    func postStatus(content: String, account: SocialAccount, replyTo: String?) async throws -> Post

    /// Fetches a specific post by ID
    /// - Parameters:
    ///   - id: The ID of the post to fetch
    ///   - account: The account to fetch with
    /// - Returns: The requested post
    func fetchPost(id: String, account: SocialAccount) async throws -> Post
}

/// A client for interacting with the Mastodon API
public class MastodonAPIClientImpl: MastodonAPIClient {
    // MARK: - Properties

    private let logger = Logger(subsystem: "com.socialfusion", category: "MastodonAPIClient")
    private let session: URLSession
    private let postNormalizer: PostNormalizer

    // MARK: - Initialization

    public init(session: URLSession = .shared, postNormalizer: PostNormalizer) {
        self.session = session
        self.postNormalizer = postNormalizer
    }

    // MARK: - Public Methods

    /// Fetch a post by its ID
    public func fetchPost(id: String, token: String) async throws -> MastodonPost {
        let url = try makeURL(path: "/api/v1/statuses/\(id)")
        let request = try makeRequest(url: url, token: token)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MastodonError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(MastodonPost.self, from: data)
        case 401:
            throw MastodonError.unauthorized
        case 404:
            throw MastodonError.notFound
        default:
            throw MastodonError.serverError(httpResponse.statusCode)
        }
    }

    /// Like a post
    public func likePost(id: String, token: String) async throws {
        let url = try makeURL(path: "/api/v1/statuses/\(id)/favourite")
        let request = try makeRequest(url: url, method: "POST", token: token)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MastodonError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return
        case 401:
            throw MastodonError.unauthorized
        case 404:
            throw MastodonError.notFound
        default:
            throw MastodonError.serverError(httpResponse.statusCode)
        }
    }

    /// Unlike a post
    public func unlikePost(id: String, token: String) async throws {
        let url = try makeURL(path: "/api/v1/statuses/\(id)/unfavourite")
        let request = try makeRequest(url: url, method: "POST", token: token)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MastodonError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return
        case 401:
            throw MastodonError.unauthorized
        case 404:
            throw MastodonError.notFound
        default:
            throw MastodonError.serverError(httpResponse.statusCode)
        }
    }

    /// Repost a post
    public func repostPost(id: String, token: String) async throws {
        let url = try makeURL(path: "/api/v1/statuses/\(id)/reblog")
        let request = try makeRequest(url: url, method: "POST", token: token)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MastodonError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return
        case 401:
            throw MastodonError.unauthorized
        case 404:
            throw MastodonError.notFound
        default:
            throw MastodonError.serverError(httpResponse.statusCode)
        }
    }

    /// Unrepost a post
    public func unrepostPost(id: String, token: String) async throws {
        let url = try makeURL(path: "/api/v1/statuses/\(id)/unreblog")
        let request = try makeRequest(url: url, method: "POST", token: token)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MastodonError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return
        case 401:
            throw MastodonError.unauthorized
        case 404:
            throw MastodonError.notFound
        default:
            throw MastodonError.serverError(httpResponse.statusCode)
        }
    }

    /// Reply to a post
    public func replyToPost(id: String, content: String, token: String) async throws -> MastodonPost
    {
        let url = try makeURL(path: "/api/v1/statuses")
        var request = try makeRequest(url: url, method: "POST", token: token)

        // Add request body
        let body = [
            "status": content,
            "in_reply_to_id": id,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MastodonError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(MastodonPost.self, from: data)
        case 401:
            throw MastodonError.unauthorized
        case 404:
            throw MastodonError.notFound
        default:
            throw MastodonError.serverError(httpResponse.statusCode)
        }
    }

    /// Fetch the timeline for an account
    public func fetchTimeline(token: String) async throws -> [MastodonPost] {
        let url = try makeURL(path: "/api/v1/timelines/home")
        let request = try makeRequest(url: url, token: token)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MastodonError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode([MastodonPost].self, from: data)
        case 401:
            throw MastodonError.unauthorized
        default:
            throw MastodonError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Protocol Implementation
    public func fetchTimeline(for account: SocialAccount) async throws -> [Post] {
        let token = try await account.getValidAccessToken()
        let mastodonPosts = try await fetchTimeline(token: token)
        return try mastodonPosts.map { try postNormalizer.normalize($0) }
    }

    public func postStatus(content: String, account: SocialAccount, replyTo: String?) async throws
        -> Post
    {
        let token = try await account.getValidAccessToken()
        let mastodonPost: MastodonPost
        if let replyTo = replyTo {
            mastodonPost = try await replyToPost(id: replyTo, content: content, token: token)
        } else {
            mastodonPost = try await createPost(content: content, token: token)
        }
        return try postNormalizer.normalize(mastodonPost)
    }

    public func fetchPost(id: String, account: SocialAccount) async throws -> Post {
        let token = try await account.getValidAccessToken()
        let mastodonPost = try await fetchPost(id: id, token: token)
        return try postNormalizer.normalize(mastodonPost)
    }

    // MARK: - Private Methods

    private func makeURL(path: String) throws -> URL {
        guard let url = URL(string: "https://mastodon.social\(path)") else {
            throw MastodonError.invalidURL
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

    private func createPost(content: String, token: String) async throws -> MastodonPost {
        let url = try makeURL(path: "/api/v1/statuses")
        var request = try makeRequest(url: url, method: "POST", token: token)

        let body = ["status": content]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MastodonError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(MastodonPost.self, from: data)
        case 401:
            throw MastodonError.unauthorized
        case 404:
            throw MastodonError.notFound
        default:
            throw MastodonError.serverError(httpResponse.statusCode)
        }
    }
}

// MARK: - Errors
public enum MastodonError: Error {
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case serverError(Int)
}

// MARK: - Preview Helper
extension MastodonAPIClient {
    static var preview: MastodonAPIClient {
        MastodonAPIClientImpl()
    }
}
