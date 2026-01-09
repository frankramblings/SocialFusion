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
    /// An error that occurred during file operations.
    case fileError(FileError)
    /// An error that occurred during database operations.
    case databaseError(DatabaseError)
    /// An error that occurred during configuration.
    case configurationError(String)
    /// An error that occurred during validation.
    case validationError([ValidationError])
    /// An unknown error occurred.
    case unknown(Error)

    /// Errors that can occur during file operations.
    public enum FileError {
        case fileNotFound(String)
        case permissionDenied(String)
        case invalidPath(String)
        case readError(Error)
        case writeError(Error)
        case deleteError(Error)
    }

    /// Errors that can occur during database operations.
    public enum DatabaseError {
        case connectionError(Error)
        case queryError(Error)
        case constraintViolation(String)
        case transactionError(Error)
        case migrationError(Error)
    }

    /// Errors that can occur during validation.
    public struct ValidationError: LocalizedError {
        public let field: String
        public let message: String

        public init(field: String, message: String) {
            self.field = field
            self.message = message
        }

        public var errorDescription: String? {
            "\(field): \(message)"
        }
    }

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
        case .fileError(let error):
            return "File error: \(error.localizedDescription)"
        case .databaseError(let error):
            return "Database error: \(error.localizedDescription)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .validationError(let errors):
            return
                "Validation errors: \(errors.map { $0.errorDescription ?? "" }.joined(separator: ", "))"
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
        case .fileError(let error):
            return error.recoverySuggestion
        case .databaseError(let error):
            return error.recoverySuggestion
        case .configurationError:
            return "Please check your configuration settings and try again."
        case .validationError:
            return "Please correct the validation errors and try again."
        case .unknown:
            return "Please try again or contact support if the problem persists."
        }
    }
}

extension AppError.FileError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .readError(let error):
            return "Read error: \(error.localizedDescription)"
        case .writeError(let error):
            return "Write error: \(error.localizedDescription)"
        case .deleteError(let error):
            return "Delete error: \(error.localizedDescription)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .fileNotFound:
            return "Please check if the file exists and try again."
        case .permissionDenied:
            return "Please check your file permissions and try again."
        case .invalidPath:
            return "Please check the file path and try again."
        case .readError, .writeError, .deleteError:
            return "Please try again or contact support if the problem persists."
        }
    }
}

extension AppError.DatabaseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connectionError(let error):
            return "Connection error: \(error.localizedDescription)"
        case .queryError(let error):
            return "Query error: \(error.localizedDescription)"
        case .constraintViolation(let message):
            return "Constraint violation: \(message)"
        case .transactionError(let error):
            return "Transaction error: \(error.localizedDescription)"
        case .migrationError(let error):
            return "Migration error: \(error.localizedDescription)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .connectionError:
            return "Please check your database connection and try again."
        case .queryError:
            return "Please check your query and try again."
        case .constraintViolation:
            return "Please check your data and try again."
        case .transactionError:
            return "Please try again or contact support if the problem persists."
        case .migrationError:
            return "Please check your migration scripts and try again."
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
