import Foundation

/// Network-related errors with consistent handling across the app
enum NetworkError: Error {
    case requestFailed(Error)
    case httpError(Int, String?)
    case noData
    case decodingError(Error)
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
}

extension NetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .httpError(let statusCode, let message):
            if let message = message, !message.isEmpty {
                return "HTTP error \(statusCode): \(message)"
            }
            return "HTTP error: \(statusCode)"
        case .noData:
            return "No data received"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .invalidURL:
            return "Invalid URL"
        case .cancelled:
            return "Request was cancelled"
        case .duplicateRequest:
            return "Duplicate request detected"
        case .timeout:
            return "Request timed out"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .unauthorized:
            return "Authentication required"
        case .serverError:
            return "Server error occurred"
        case .accessDenied:
            return "Access denied"
        case .resourceNotFound:
            return "Resource not found"
        case .blockedDomain(let domain):
            return "Domain blocked: \(domain)"
        case .unsupportedResponse:
            return "Unsupported response format"
        case .networkUnavailable:
            return "Network connection unavailable"
        }
    }

    /// Returns a user-friendly version of the error message
    var userFriendlyDescription: String {
        switch self {
        case .requestFailed:
            return "Network connection problem"
        case .httpError(let statusCode, _):
            if statusCode == 404 {
                return "Content not found"
            } else if statusCode == 401 || statusCode == 403 {
                return "Access not authorized"
            } else if statusCode >= 500 {
                return "Server temporarily unavailable"
            }
            return "Connection error"
        case .noData:
            return "No data received"
        case .decodingError:
            return "Could not read the response"
        case .invalidURL:
            return "Invalid link"
        case .cancelled:
            return "Request cancelled"
        case .duplicateRequest:
            return "Request already in progress"
        case .timeout:
            return "Connection timed out"
        case .rateLimitExceeded:
            return "Too many requests. Please wait."
        case .unauthorized:
            return "Please sign in again"
        case .serverError:
            return "Server temporarily unavailable"
        case .accessDenied:
            return "Access denied"
        case .resourceNotFound:
            return "Content not found"
        case .blockedDomain:
            return "This domain is not supported"
        case .unsupportedResponse:
            return "Unsupported content type"
        case .networkUnavailable:
            return "No network connection"
        }
    }

    /// Determines if this error is retriable
    var isRetriable: Bool {
        switch self {
        case .requestFailed,
            .httpError(let code, _) where code >= 500, .timeout, .networkUnavailable:
            return true
        case .rateLimitExceeded:
            return true
        default:
            return false
        }
    }

    /// Maps NSError and HTTPURLResponse to appropriate NetworkError types
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
}
