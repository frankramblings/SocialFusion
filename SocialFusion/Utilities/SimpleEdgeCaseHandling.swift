import SwiftUI
import Network

/// Simple edge case monitoring for basic app state management
@MainActor
class SimpleEdgeCaseMonitor: ObservableObject {
    static let shared = SimpleEdgeCaseMonitor()
    
    @Published var isNetworkAvailable: Bool = true
    @Published var hasAccounts: Bool = false
    @Published var isLowMemory: Bool = false
    
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    
    private init() {
        setupNetworkMonitoring()
        setupMemoryMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        networkMonitor.start(queue: networkQueue)
    }
    
    private func setupMemoryMonitoring() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isLowMemory = true
                // Reset after 30 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    await MainActor.run {
                        self?.isLowMemory = false
                    }
                }
            }
        }
    }
    
    func updateAccountStatus(hasAccounts: Bool) {
        Task { @MainActor in
            self.hasAccounts = hasAccounts
        }
    }
    
    deinit {
        networkMonitor.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}

/// Simple empty state view for basic edge case handling
struct SimpleEmptyStateView: View {
    enum StateType {
        case loading
        case noAccounts
        case noInternet
        case noPostsYet
        case lowMemory
    }
    
    let state: StateType
    let onRetry: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 16) {
            image
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.title2)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
            
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if let onRetry = onRetry, state != .loading {
                Button("Retry") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var image: some View {
        switch state {
        case .loading:
            ProgressView()
                .scaleEffect(1.5)
        case .noAccounts:
            Image(systemName: "person.crop.circle.badge.questionmark")
        case .noInternet:
            Image(systemName: "wifi.slash")
        case .noPostsYet:
            Image(systemName: "timeline.selection")
        case .lowMemory:
            Image(systemName: "memorychip")
        }
    }
    
    private var title: String {
        switch state {
        case .loading:
            return "Loading timeline..."
        case .noAccounts:
            return "No accounts added"
        case .noInternet:
            return "No internet connection"
        case .noPostsYet:
            return "No posts yet"
        case .lowMemory:
            return "Low memory"
        }
    }
    
    private var message: String {
        switch state {
        case .loading:
            return "Please wait while we fetch your timeline."
        case .noAccounts:
            return "Add your Mastodon or Bluesky accounts to see posts here."
        case .noInternet:
            return "Please check your network connection and try again."
        case .noPostsYet:
            return "Pull to refresh or add some accounts to get started."
        case .lowMemory:
            return "The app is running low on memory. Some features may be limited."
        }
    }
}
