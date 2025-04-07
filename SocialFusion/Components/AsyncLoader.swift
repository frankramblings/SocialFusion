import SwiftUI

/// A generic AsyncLoader that helps manage asynchronous data loading with error handling and loading states
struct AsyncLoader<T, Content: View, EmptyContent: View>: View {
    @State private var state: LoadingState<T> = .loading
    @State private var error: AppError? = nil

    private let loadFunction: () async throws -> T
    private let content: (T) -> Content
    private let emptyContent: () -> EmptyContent
    private let emptyCheck: (T) -> Bool

    /// Initialize with an async loading function and views for different states
    /// - Parameters:
    ///   - loadFunction: The async function that loads the data
    ///   - content: View builder for the loaded content
    ///   - emptyContent: View builder for empty state
    ///   - emptyCheck: Function to determine if data is empty
    init(
        load loadFunction: @escaping () async throws -> T,
        @ViewBuilder content: @escaping (T) -> Content,
        @ViewBuilder emptyContent: @escaping () -> EmptyContent,
        emptyCheck: @escaping (T) -> Bool = { _ in false }
    ) {
        self.loadFunction = loadFunction
        self.content = content
        self.emptyContent = emptyContent
        self.emptyCheck = emptyCheck
    }

    var body: some View {
        LoadingStateView(
            state: state.map(content),
            emptyContent: emptyContent,
            retryAction: load
        )
        .task {
            await load()
        }
        .handleAppErrors(error: $error) {
            // Retry action
            Task {
                await load()
            }
        }
    }

    /// Load data and update state accordingly
    @MainActor
    private func load() async {
        // Only show loading indicator for initial load
        if case .error = state {
            // If we're retrying after an error, keep the error state visible
            // until we have new data
        } else {
            state = .loading
        }

        do {
            let result = try await loadFunction()

            // Check if result is empty
            if emptyCheck(result) {
                state = .empty
            } else {
                state = .loaded(result)
            }
        } catch {
            // Convert to app error and present
            let appError = convertToAppError(error)
            self.error = appError
            state = .error(error)
        }
    }

    /// Convert standard error to AppError
    private func convertToAppError(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        // Let ErrorHandler do the conversion for us
        return ErrorHandler.shared.mapToAppError(error) {
            Task {
                await load()
            }
        }
    }
}

// MARK: - Helper Extensions

extension LoadingState {
    /// Maps the loaded value using a transform function
    func map<U>(_ transform: @escaping (T) -> U) -> LoadingState<U> {
        switch self {
        case .loading:
            return .loading
        case .loaded(let value):
            return .loaded(transform(value))
        case .error(let error):
            return .error(error)
        case .empty:
            return .empty
        }
    }
}

extension ErrorHandler {
    /// Make this method public for AsyncLoader
    func mapToAppError(_ error: Error, retryAction: (() -> Void)? = nil) -> AppError {
        // Try to map NetworkError to AppError
        if let networkError = error as? NetworkError {
            let isRetryable = networkError.isRetriable

            switch networkError {
            case .unauthorized, .accessDenied:
                return AppError(
                    type: .authentication,
                    message: networkError.userFriendlyDescription,
                    underlyingError: networkError,
                    isRetryable: isRetryable,
                    suggestedAction: retryAction
                )

            case .invalidURL, .blockedDomain, .unsupportedResponse:
                return AppError(
                    type: .data,
                    message: networkError.userFriendlyDescription,
                    underlyingError: networkError,
                    isRetryable: false
                )

            default:
                return AppError(
                    type: .network,
                    message: networkError.userFriendlyDescription,
                    underlyingError: networkError,
                    isRetryable: isRetryable,
                    suggestedAction: retryAction
                )
            }
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
}

// MARK: - Convenience Extensions

extension AsyncLoader where EmptyContent == EmptyStateView {
    /// Initialize with a default empty state view
    init(
        load loadFunction: @escaping () async throws -> T,
        @ViewBuilder content: @escaping (T) -> Content,
        emptyMessage: String = "No content available",
        emptySystemImage: String = "tray",
        emptyCheck: @escaping (T) -> Bool = { _ in false }
    ) {
        self.loadFunction = loadFunction
        self.content = content
        self.emptyContent = {
            EmptyStateView(
                message: emptyMessage,
                systemImage: emptySystemImage
            )
        }
        self.emptyCheck = emptyCheck
    }
}

extension AsyncLoader where T: Collection, EmptyContent == EmptyStateView {
    /// Initialize for collections with automatic empty check
    init(
        load loadFunction: @escaping () async throws -> T,
        @ViewBuilder content: @escaping (T) -> Content,
        emptyMessage: String = "No items available",
        emptySystemImage: String = "tray"
    ) {
        self.loadFunction = loadFunction
        self.content = content
        self.emptyContent = {
            EmptyStateView(
                message: emptyMessage,
                systemImage: emptySystemImage
            )
        }
        self.emptyCheck = { $0.isEmpty }
    }
}
