import Foundation
import os.log

/// A unified protocol for networking errors across the app
public enum NetworkError: Error {
    case requestFailed(Error)
    case httpError(Int, String?)
    case noData
    case decodingError
    case invalidURL
    case cancelled
    case duplicateRequest
    case timeout
    case rateLimitExceeded(retryAfter: TimeInterval?)
    case unauthorized
    case serverError
    case accessDenied
    case resourceNotFound
    case blockedDomain(String)
    case unsupportedResponse
    case networkUnavailable
    case apiError(String)

    static func from(error: Error?, response: URLResponse?) -> NetworkError {
        // First handle NSError types
        if let nsError = error as NSError? {
            switch nsError.domain {
            case NSURLErrorDomain:
                switch nsError.code {
                case NSURLErrorTimedOut:
                    return .timeout
                case NSURLErrorCancelled:
                    return .cancelled
                case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                    return .networkUnavailable
                default:
                    return .requestFailed(nsError)
                }
            default:
                return .requestFailed(nsError)
            }
        }

        // Then handle HTTP response codes
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200...299:  // Success range, should not be an error
                return .noData  // Default if no specific error but in success range
            case 401:
                return .unauthorized
            case 403:
                return .accessDenied
            case 404:
                return .resourceNotFound
            case 429:
                // Check for Retry-After header
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                let retryTime = retryAfter.flatMap(TimeInterval.init) ?? 60
                return .rateLimitExceeded(retryAfter: retryTime)
            case 400...499:
                return .httpError(httpResponse.statusCode, nil)
            case 500...599:
                return .serverError
            default:
                return .httpError(httpResponse.statusCode, nil)
            }
        }

        // Default case if we can't categorize
        return .requestFailed(error ?? NSError(domain: "Unknown", code: -1, userInfo: nil))
    }

    var isRetriable: Bool {
        switch self {
        case .timeout, .networkUnavailable, .serverError, .rateLimitExceeded:
            return true
        default:
            return false
        }
    }

    // User-friendly error messages
    var userFriendlyDescription: String {
        switch self {
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .httpError(let code, let message):
            return message ?? "HTTP error: \(code)"
        case .noData:
            return "No data received"
        case .decodingError:
            return "Could not process the data from the server"
        case .invalidURL:
            return "Invalid URL"
        case .cancelled:
            return "Request was cancelled"
        case .duplicateRequest:
            return "Duplicate request detected"
        case .timeout:
            return "Request timed out"
        case .rateLimitExceeded:
            return "Too many requests. Please try again later."
        case .unauthorized:
            return "Authentication required"
        case .serverError:
            return "Server error occurred"
        case .accessDenied:
            return "Access denied"
        case .resourceNotFound:
            return "Resource not found"
        case .blockedDomain(let domain):
            return "Domain is blocked: \(domain)"
        case .unsupportedResponse:
            return "Unsupported response format"
        case .networkUnavailable:
            return "Network connection unavailable"
        case .apiError(let message):
            return message
        }
    }
}

/// A centralized service for handling all network requests
public class NetworkService {
    // MARK: - Properties

    public static let shared = NetworkService()

    private let session: URLSession
    private let logger = Logger(subsystem: "com.socialfusion", category: "NetworkService")
    private let connectionManager = ConnectionManager.shared

    // MARK: - Initialization

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = NetworkConfig.defaultRequestTimeout
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = NetworkConfig.maxConcurrentConnections

        session = URLSession(configuration: config)
    }

    // MARK: - Public Methods

    /// Perform a GET request
    public func get<T: Decodable>(
        url: URL,
        headers: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        responseType: T.Type
    ) async throws -> T {
        try await request(
            url: url,
            method: "GET",
            headers: headers,
            queryItems: queryItems,
            body: nil as String?,
            responseType: responseType
        )
    }

    /// Perform a POST request with a JSON body
    public func post<T: Decodable, U: Encodable>(
        url: URL,
        headers: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        body: U?,
        responseType: T.Type
    ) async throws -> T {
        try await request(
            url: url,
            method: "POST",
            headers: headers,
            queryItems: queryItems,
            body: body,
            responseType: responseType
        )
    }

    /// Perform a PUT request with a JSON body
    public func put<T: Decodable, U: Encodable>(
        url: URL,
        headers: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        body: U?,
        responseType: T.Type
    ) async throws -> T {
        try await request(
            url: url,
            method: "PUT",
            headers: headers,
            queryItems: queryItems,
            body: body,
            responseType: responseType
        )
    }

    /// Perform a DELETE request
    public func delete<T: Decodable>(
        url: URL,
        headers: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        responseType: T.Type
    ) async throws -> T {
        try await request(
            url: url,
            method: "DELETE",
            headers: headers,
            queryItems: queryItems,
            body: nil as String?,
            responseType: responseType
        )
    }

    /// Generic request method that handles all HTTP methods
    public func request<T: Decodable, U: Encodable>(
        url: URL,
        method: String,
        headers: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        body: U?,
        responseType: T.Type
    ) async throws -> T {
        // Build URL with query parameters if provided
        var finalURL = url
        if let queryItems = queryItems, !queryItems.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
            components?.queryItems = queryItems
            finalURL = components?.url ?? url
        }

        // Create request
        var request = URLRequest(url: finalURL)
        request.httpMethod = method

        // Add common headers
        for (key, value) in NetworkConfig.commonHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Add custom headers
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Add JSON body if provided
        if let body = body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            do {
                request.httpBody = try encoder.encode(body)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } catch {
                logger.error(
                    "Failed to encode request body: \(error.localizedDescription, privacy: .public)"
                )
                throw NetworkError.requestFailed(error)
            }
        }

        // Log request details
        logger.debug(
            "Sending \(method, privacy: .public) request to \(finalURL.absoluteString, privacy: .public)"
        )

        do {
            // Send the request
            let (data, response) = try await session.data(for: request)

            // Check response status
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Response is not HTTPURLResponse")
                throw NetworkError.unsupportedResponse
            }

            // Log response details
            logger.debug(
                "Received status code \(httpResponse.statusCode, privacy: .public) from \(finalURL.absoluteString, privacy: .public)"
            )

            // Check for error status codes
            guard (200...299).contains(httpResponse.statusCode) else {
                // Try to extract error message from response
                var errorMessage: String? = nil
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    errorMessage = json["error"] as? String ?? json["message"] as? String
                }

                let error = NetworkError.httpError(httpResponse.statusCode, errorMessage)
                logger.error("HTTP error: \(error.userFriendlyDescription, privacy: .public)")
                throw error
            }

            // Validate data
            guard !data.isEmpty else {
                logger.error("Response contained no data")
                throw NetworkError.noData
            }

            // Decode the response
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                decoder.dateDecodingStrategy = .iso8601

                return try decoder.decode(responseType, from: data)
            } catch {
                logger.error(
                    "Failed to decode response: \(error.localizedDescription, privacy: .public)")

                // Log data for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    let previewLength = min(jsonString.count, 200)
                    let preview = String(jsonString.prefix(previewLength))
                    logger.debug("Response data preview: \(preview, privacy: .private)")
                }

                throw NetworkError.decodingError
            }
        } catch {
            // Convert to standard NetworkError if not already
            if let networkError = error as? NetworkError {
                throw networkError
            } else {
                let networkError = NetworkError.from(error: error, response: nil)
                logger.error(
                    "Request failed: \(networkError.userFriendlyDescription, privacy: .public)")
                throw networkError
            }
        }
    }

    /// Download data from a URL
    public func downloadData(from url: URL) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.unsupportedResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw NetworkError.httpError(httpResponse.statusCode, nil)
            }

            return data
        } catch {
            if let networkError = error as? NetworkError {
                throw networkError
            } else {
                throw NetworkError.from(error: error, response: nil)
            }
        }
    }

    /// Cancel all ongoing requests
    public func cancelAllRequests() {
        connectionManager.cancelAllRequests()
    }
}
