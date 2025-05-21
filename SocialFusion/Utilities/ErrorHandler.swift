import Combine
import Foundation
import SwiftUI
import UIKit

/// Types of errors that can occur in the app
enum AppErrorType {
    case network
    case authentication
    case data
    case permission
    case account
    case general
}

/// Standard application error
struct AppError: Error, Identifiable {
    var id = UUID()
    let type: AppErrorType
    let message: String
    let underlyingError: Error?
    let isRetryable: Bool
    let suggestedAction: (() -> Void)?

    init(
        type: AppErrorType,
        message: String,
        underlyingError: Error? = nil,
        isRetryable: Bool = false,
        suggestedAction: (() -> Void)? = nil
    ) {
        self.type = type
        self.message = message
        self.underlyingError = underlyingError
        self.isRetryable = isRetryable
        self.suggestedAction = suggestedAction
    }
}

/// Centralized error handler to manage errors consistently across the app
class ErrorHandler {
    static let shared = ErrorHandler()

    // Published property to expose the current error
    @Published var currentError: AppError? = nil

    // Subject for handling errors via Combine
    let errorPublisher = PassthroughSubject<AppError, Never>()

    private init() {
        // Listen for notifications about errors
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleErrorNotification(_:)),
            name: .appErrorOccurred,
            object: nil
        )
    }

    /// Handle an error by processing it and notifying appropriate systems
    func handleError(_ error: Error, retryAction: (() -> Void)? = nil) {
        let appError = mapToAppError(error, retryAction: retryAction)

        // Publish the error for subscribers
        currentError = appError
        errorPublisher.send(appError)

        // Post a notification for parts of the app not using Combine
        NotificationCenter.default.post(
            name: .appErrorOccurred,
            object: nil,
            userInfo: ["error": appError]
        )

        // Log the error
        logError(appError)
    }

    /// Show an error alert if appropriate
    func showErrorAlert(on viewController: UIViewController?, error: AppError) {
        guard let viewController = viewController else { return }

        let alert = UIAlertController(
            title: errorTitle(for: error.type),
            message: error.message,
            preferredStyle: .alert
        )

        // Add OK action
        alert.addAction(UIAlertAction(title: "OK", style: .default))

        // Add retry action if available
        if error.isRetryable, let action = error.suggestedAction {
            alert.addAction(
                UIAlertAction(title: "Retry", style: .default) { _ in
                    action()
                })
        }

        viewController.present(alert, animated: true)
    }

    /// Convert a standard Error to our AppError type
    private func mapToAppError(_ error: Error, retryAction: (() -> Void)? = nil) -> AppError {
        // Try to map NetworkError to AppError
        if let networkError = error as? NetworkError {
            // Comment out or stub the use of 'isRetriable' and 'userFriendlyDescription' on NetworkError
            // TODO: Implement these properties/methods as needed
            // Example:
            // let isRetryable = networkError.isRetriable // TODO: Implement
            // message: networkError.userFriendlyDescription // TODO: Implement

            return AppError(
                type: .network,
                message: String(describing: networkError),
                underlyingError: networkError,
                isRetryable: false,
                suggestedAction: retryAction
            )
        }

        // Try to map ServiceError to AppError
        if let serviceError = error as? ServiceError {
            switch serviceError {
            case .invalidAccount, .duplicateAccount:
                return AppError(
                    type: .account,
                    message: serviceError.errorDescription ?? "Account error",
                    underlyingError: serviceError,
                    isRetryable: false
                )

            case .authenticationFailed:
                return AppError(
                    type: .authentication,
                    message: serviceError.errorDescription ?? "Authentication failed",
                    underlyingError: serviceError,
                    isRetryable: true,
                    suggestedAction: retryAction
                )

            case .networkError:
                return AppError(
                    type: .network,
                    message: serviceError.errorDescription ?? "Network error",
                    underlyingError: serviceError,
                    isRetryable: true,
                    suggestedAction: retryAction
                )

            default:
                return AppError(
                    type: .general,
                    message: serviceError.errorDescription ?? "An error occurred",
                    underlyingError: serviceError,
                    isRetryable: false
                )
            }
        }

        // Default error handling
        return AppError(
            type: .general,
            message: error.localizedDescription,
            underlyingError: error,
            isRetryable: false
        )
    }

    /// Get an appropriate title for error alerts based on error type
    func errorTitle(for type: AppErrorType) -> String {
        switch type {
        case .network:
            return "Connection Error"
        case .authentication:
            return "Authentication Error"
        case .data:
            return "Data Error"
        case .permission:
            return "Permission Required"
        case .account:
            return "Account Error"
        case .general:
            return "Error"
        }
    }

    /// Log error details for debugging
    private func logError(_ error: AppError) {
        // Basic console logging
        print("ERROR [\(error.type)] \(error.message)")

        if let underlying = error.underlyingError {
            print("  Underlying: \(underlying)")
        }

        // In a real app, we might send errors to a logging service
    }

    /// Handle error notifications
    @objc private func handleErrorNotification(_ notification: Notification) {
        if let error = notification.userInfo?["error"] as? AppError {
            // Set as current error
            currentError = error

            // Could add additional error handling here
        }
    }
}

// Convenience extension for SwiftUI view error handling
extension View {
    /// Handle errors in SwiftUI views
    func handleAppErrors(
        error: Binding<AppError?>,
        retryAction: (() -> Void)? = nil
    ) -> some View {
        self.alert(item: error) { appError in
            if appError.isRetryable && appError.suggestedAction != nil {
                return Alert(
                    title: Text(ErrorHandler.shared.errorTitle(for: appError.type)),
                    message: Text(appError.message),
                    primaryButton: .default(Text("Retry")) {
                        appError.suggestedAction?()
                    },
                    secondaryButton: .cancel(Text("OK"))
                )
            } else {
                return Alert(
                    title: Text(ErrorHandler.shared.errorTitle(for: appError.type)),
                    message: Text(appError.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}

// MARK: - Helpers and Extensions

extension Notification.Name {
    static let appErrorOccurred = Notification.Name("AppErrorOccurred")
}
