import Foundation
import SwiftUI

/// Represents the state of loading data
enum LoadingState<T> {
    case loading
    case loaded(T)
    case error(Error)
    case empty
}

/// A view that displays different content based on the loading state
struct LoadingStateView<Content: View, EmptyContent: View>: View {
    let state: LoadingState<Content>
    let emptyContent: () -> EmptyContent
    let retryAction: () -> Void

    var body: some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let content):
            content
        case .empty:
            emptyContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error:
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.orange)

                Text("Something went wrong")
                    .font(.headline)

                Button("Try Again") {
                    retryAction()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A view that displays an empty state with a message and icon
struct EmptyStateView: View {
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text(message)
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

/// Previews for the EmptyStateView
#Preview {
    VStack(spacing: 20) {
        EmptyStateView(message: "No posts found", systemImage: "tray")
            .frame(height: 200)
            .background(Color(.systemGroupedBackground))
            .cornerRadius(12)

        LoadingStateView<AnyView, EmptyStateView>(
            state: .loading,
            emptyContent: { EmptyStateView(message: "Nothing here", systemImage: "tray") },
            retryAction: {}
        )
        .frame(height: 200)
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)

        LoadingStateView<AnyView, EmptyStateView>(
            state: .error(NSError(domain: "test", code: 1, userInfo: nil)),
            emptyContent: { EmptyStateView(message: "Nothing here", systemImage: "tray") },
            retryAction: {}
        )
        .frame(height: 200)
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    .padding()
}
