import SwiftUI

/// LoadingState enum to handle different UI states consistently
enum LoadingState<T> {
    case loading
    case loaded(T)
    case error(Error)
    case empty
}

/// A view that shows different content based on loading state
struct LoadingStateView<Content: View, EmptyContent: View>: View {
    let state: LoadingState<Content>
    let emptyContent: EmptyContent
    let retryAction: (() -> Void)?

    /// Initialize with a loading state, empty content and optional retry action
    init(
        state: LoadingState<Content>,
        @ViewBuilder emptyContent: () -> EmptyContent,
        retryAction: (() -> Void)? = nil
    ) {
        self.state = state
        self.emptyContent = emptyContent()
        self.retryAction = retryAction
    }

    var body: some View {
        switch state {
        case .loading:
            loadingView
        case .loaded(let content):
            content
        case .error(let error):
            errorView(for: error)
        case .empty:
            emptyContent
        }
    }

    // Loading spinner view
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle())

            Text("Loading...")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }

    // Error view with retry button if available
    private func errorView(for error: Error) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.red)

            Text(errorMessage(from: error))
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if let retryAction = retryAction {
                Button(action: retryAction) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }

    // Get a user-friendly error message
    private func errorMessage(from error: Error) -> String {
        if let networkError = error as? NetworkError {
            return networkError.userFriendlyDescription
        } else if let appError = error as? AppError {
            return appError.message
        } else {
            return error.localizedDescription
        }
    }
}

/// Extension for simplified usage with default empty state
extension LoadingStateView where EmptyContent == EmptyStateView {
    init(
        state: LoadingState<Content>,
        message: String = "No content available",
        systemImage: String = "tray",
        retryAction: (() -> Void)? = nil
    ) {
        self.state = state
        self.emptyContent = EmptyStateView(message: message, systemImage: systemImage)
        self.retryAction = retryAction
    }
}

/// Standard empty state view
struct EmptyStateView: View {
    let message: String
    let systemImage: String
    let action: (() -> Void)?
    let actionTitle: String?

    init(
        message: String,
        systemImage: String = "tray",
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text(message)
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if let action = action, let actionTitle = actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
}
