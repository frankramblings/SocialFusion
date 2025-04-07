import Foundation

/// A namespace for application-specific errors.
public enum AppError: LocalizedError {
    /// An error that occurred during network operations.
    case networkError(underlyingError: Error)
    /// An error that occurred during data parsing.
    case parsingError(underlyingError: Error)
    /// An error that occurred due to invalid input.
    case invalidInput(String)
    /// An error that occurred due to an unexpected state.
    case unexpectedState(String)
    /// An error that occurred during authentication.
    case authenticationError(String)
    /// An error that occurred during authorization.
    case authorizationError(String)
    /// An unknown error occurred.
    case unknown(Error)

    public var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parsingError(let error):
            return "Parsing error: \(error.localizedDescription)"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .unexpectedState(let message):
            return "Unexpected state: \(message)"
        case .authenticationError(let message):
            return "Authentication error: \(message)"
        case .authorizationError(let message):
            return "Authorization error: \(message)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "Please check your internet connection and try again."
        case .parsingError:
            return "Please try again later or contact support if the problem persists."
        case .invalidInput:
            return "Please check your input and try again."
        case .unexpectedState:
            return "Please try again or contact support if the problem persists."
        case .authenticationError:
            return "Please check your credentials and try again."
        case .authorizationError:
            return "Please check your permissions and try again."
        case .unknown:
            return "Please try again or contact support if the problem persists."
        }
    }
}

/// A protocol for types that can be converted to an `AppError`.
public protocol AppErrorConvertible {
    /// Converts the receiver to an `AppError`.
    func asAppError() -> AppError
}

extension Error {
    /// Converts any `Error` to an `AppError`.
    public func asAppError() -> AppError {
        if let appError = self as? AppError {
            return appError
        }
        return .unknown(self)
    }
}
