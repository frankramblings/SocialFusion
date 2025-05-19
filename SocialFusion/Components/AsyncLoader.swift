import SwiftUI

/// A generic AsyncLoader that helps manage asynchronous data loading with error handling and loading states
struct AsyncLoader<T, Content: View, EmptyContent: View>: View {
    @State private var state: LoadingState<T> = .loading
    @State private var error: Error? = nil

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
            retryAction: {
                Task {
                    await load()
                }
            }
        )
        .task {
            await load()
        }
        .alert(
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )
        ) {
            Alert(
                title: Text("Error"),
                message: Text(error?.localizedDescription ?? "An unknown error occurred"),
                dismissButton: .default(Text("OK"))
            )
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
            // Set the error for the alert
            self.error = error
            state = .error(error)
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
