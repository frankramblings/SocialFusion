import Foundation
import Network
import SwiftUI
import UIKit

/// Comprehensive edge case handler for beta readiness
/// Handles scenarios like empty states, network interruptions, memory pressure, and authentication failures
@MainActor
class EdgeCaseHandler: ObservableObject {
    static let shared = EdgeCaseHandler()

    // MARK: - Published State

    @Published var networkStatus: NetworkStatus = .unknown
    @Published var memoryPressure: MemoryPressureLevel = .normal
    @Published var authenticationState: AuthenticationState = .unknown
    @Published var currentEdgeCaseAlert: EdgeCaseAlert?

    // MARK: - Network Monitoring

    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")

    // MARK: - Memory Monitoring

    private var memoryTimer: Timer?
    private let memoryCheckInterval: TimeInterval = 10.0

    // MARK: - Configuration

    private struct Config {
        static let maxMemoryThresholdMB: Double = 300.0
        static let criticalMemoryThresholdMB: Double = 500.0
        static let maxRetryAttempts = 3
        static let retryBaseDelay: TimeInterval = 2.0
        static let networkTimeoutInterval: TimeInterval = 30.0
    }

    // MARK: - Types

    enum NetworkStatus {
        case unknown
        case available
        case unavailable
        case limited  // Cellular with restrictions
        case expensive  // Cellular data

        var isConnected: Bool {
            switch self {
            case .available, .limited, .expensive:
                return true
            case .unknown, .unavailable:
                return false
            }
        }

        var userFriendlyDescription: String {
            switch self {
            case .unknown:
                return "Checking connection..."
            case .available:
                return "Connected"
            case .unavailable:
                return "No internet connection"
            case .limited:
                return "Limited connection"
            case .expensive:
                return "Using cellular data"
            }
        }
    }

    enum MemoryPressureLevel {
        case normal
        case elevated
        case critical

        var userFriendlyDescription: String {
            switch self {
            case .normal:
                return "Memory usage normal"
            case .elevated:
                return "High memory usage"
            case .critical:
                return "Critical memory usage"
            }
        }
    }

    enum AuthenticationState {
        case unknown
        case authenticated
        case partiallyAuthenticated(failedAccounts: Int)
        case unauthenticated
        case expired

        var needsUserAction: Bool {
            switch self {
            case .unknown, .authenticated:
                return false
            case .partiallyAuthenticated, .unauthenticated, .expired:
                return true
            }
        }
    }

    struct EdgeCaseAlert: Identifiable {
        let id = UUID()
        let type: AlertType
        let title: String
        let message: String
        let primaryAction: AlertAction
        let secondaryAction: AlertAction?
        let severity: Severity

        enum AlertType {
            case networkUnavailable
            case memoryPressure
            case authenticationExpired
            case noAccountsConfigured
            case dataCorruption
            case serverUnavailable
            case rateLimitExceeded
        }

        enum Severity {
            case info
            case warning
            case critical
        }

        struct AlertAction {
            let title: String
            let action: () -> Void
        }
    }

    // MARK: - Initialization

    private init() {
        startNetworkMonitoring()
        startMemoryMonitoring()
        setupMemoryPressureObserver()
        print("🛡️ [EdgeCaseHandler] Initialized comprehensive edge case handling")
    }

    deinit {
        networkMonitor.cancel()
        memoryTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.updateNetworkStatus(path)
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    private func updateNetworkStatus(_ path: NWPath) {
        let newStatus: NetworkStatus

        switch path.status {
        case .satisfied:
            if path.isExpensive {
                newStatus = .expensive
            } else if path.isConstrained {
                newStatus = .limited
            } else {
                newStatus = .available
            }
        case .unsatisfied, .requiresConnection:
            newStatus = .unavailable
        @unknown default:
            newStatus = .unknown
        }

        // Only update if status changed
        if networkStatus != newStatus {
            let previousStatus = networkStatus
            networkStatus = newStatus

            print("🌐 [EdgeCaseHandler] Network status changed: \(previousStatus) → \(newStatus)")

            // Handle network state changes
            handleNetworkStatusChange(from: previousStatus, to: newStatus)
        }
    }

    private func handleNetworkStatusChange(from previous: NetworkStatus, to current: NetworkStatus)
    {
        switch (previous, current) {
        case (_, .unavailable):
            showNetworkUnavailableAlert()
        case (.unavailable, .available), (.unavailable, .limited), (.unavailable, .expensive):
            // Network restored - dismiss any network-related alerts
            dismissAlertIfType(.networkUnavailable)
        case (_, .expensive):
            // Switched to cellular - could show data usage warning
            break
        default:
            break
        }
    }

    // MARK: - Memory Monitoring

    private func startMemoryMonitoring() {
        memoryTimer = Timer.scheduledTimer(withTimeInterval: memoryCheckInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.checkMemoryPressure()
            }
        }
    }

    private func checkMemoryPressure() {
        let currentMemoryMB = getCurrentMemoryUsageMB()
        let newPressureLevel: MemoryPressureLevel

        if currentMemoryMB > Config.criticalMemoryThresholdMB {
            newPressureLevel = .critical
        } else if currentMemoryMB > Config.maxMemoryThresholdMB {
            newPressureLevel = .elevated
        } else {
            newPressureLevel = .normal
        }

        if memoryPressure != newPressureLevel {
            let previousLevel = memoryPressure
            memoryPressure = newPressureLevel

            print(
                "🧠 [EdgeCaseHandler] Memory pressure changed: \(previousLevel) → \(newPressureLevel) (\(String(format: "%.1f", currentMemoryMB))MB)"
            )

            handleMemoryPressureChange(newPressureLevel, memoryMB: currentMemoryMB)
        }
    }

    private func getCurrentMemoryUsageMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / (1024 * 1024)  // Convert to MB
        }

        return 0.0
    }

    private func setupMemoryPressureObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc private func didReceiveMemoryWarning() {
        print("🚨 [EdgeCaseHandler] System memory warning received")
        memoryPressure = .critical
        showMemoryPressureAlert()

        // Trigger aggressive cleanup
        NotificationCenter.default.post(name: .memoryPressureCritical, object: nil)
    }

    private func handleMemoryPressureChange(_ level: MemoryPressureLevel, memoryMB: Double) {
        switch level {
        case .normal:
            // Clear any memory-related alerts
            dismissAlertIfType(.memoryPressure)
        case .elevated:
            // Start proactive cleanup but don't alert user yet
            NotificationCenter.default.post(name: .memoryPressureElevated, object: memoryMB)
        case .critical:
            showMemoryPressureAlert()
            NotificationCenter.default.post(name: .memoryPressureCritical, object: memoryMB)
        }
    }

    // MARK: - Authentication Monitoring

    func updateAuthenticationState(totalAccounts: Int, authenticatedAccounts: Int) {
        let newState: AuthenticationState

        if totalAccounts == 0 {
            newState = .unauthenticated
        } else if authenticatedAccounts == 0 {
            newState = .expired
        } else if authenticatedAccounts < totalAccounts {
            newState = .partiallyAuthenticated(
                failedAccounts: totalAccounts - authenticatedAccounts)
        } else {
            newState = .authenticated
        }

        if authenticationState != newState {
            let previousState = authenticationState
            authenticationState = newState

            print(
                "🔐 [EdgeCaseHandler] Authentication state changed: \(previousState) → \(newState)")

            handleAuthenticationStateChange(newState)
        }
    }

    private func handleAuthenticationStateChange(_ state: AuthenticationState) {
        switch state {
        case .unauthenticated:
            showNoAccountsAlert()
        case .expired:
            showAuthenticationExpiredAlert()
        case .partiallyAuthenticated(let failedCount):
            showPartialAuthenticationAlert(failedAccounts: failedCount)
        case .authenticated:
            // Clear any auth-related alerts
            dismissAlertIfType(.authenticationExpired)
            dismissAlertIfType(.noAccountsConfigured)
        case .unknown:
            break
        }
    }

    // MARK: - Alert Management

    private func showNetworkUnavailableAlert() {
        let alert = EdgeCaseAlert(
            type: .networkUnavailable,
            title: "No Internet Connection",
            message:
                "Please check your internet connection. You can still view cached content, but new posts won't load until connection is restored.",
            primaryAction: EdgeCaseAlert.AlertAction(title: "Retry") {
                // Force a network check
                Task { @MainActor in
                    self.checkNetworkAndRetry()
                }
            },
            secondaryAction: EdgeCaseAlert.AlertAction(title: "OK") {
                self.dismissCurrentAlert()
            },
            severity: .warning
        )

        currentEdgeCaseAlert = alert
    }

    private func showMemoryPressureAlert() {
        let alert = EdgeCaseAlert(
            type: .memoryPressure,
            title: "High Memory Usage",
            message:
                "The app is using a lot of memory. Some cached content will be cleared to improve performance.",
            primaryAction: EdgeCaseAlert.AlertAction(title: "Clear Cache") {
                self.performMemoryCleanup()
                self.dismissCurrentAlert()
            },
            secondaryAction: EdgeCaseAlert.AlertAction(title: "Continue") {
                self.dismissCurrentAlert()
            },
            severity: .warning
        )

        currentEdgeCaseAlert = alert
    }

    private func showNoAccountsAlert() {
        let alert = EdgeCaseAlert(
            type: .noAccountsConfigured,
            title: "No Accounts Configured",
            message: "Add a Mastodon or Bluesky account to start viewing your timeline.",
            primaryAction: EdgeCaseAlert.AlertAction(title: "Add Account") {
                // This should trigger navigation to account setup
                NotificationCenter.default.post(name: .showAccountSetup, object: nil)
                self.dismissCurrentAlert()
            },
            secondaryAction: nil,
            severity: .info
        )

        currentEdgeCaseAlert = alert
    }

    private func showAuthenticationExpiredAlert() {
        let alert = EdgeCaseAlert(
            type: .authenticationExpired,
            title: "Authentication Expired",
            message:
                "Your account credentials have expired. Please re-authenticate to continue viewing your timeline.",
            primaryAction: EdgeCaseAlert.AlertAction(title: "Re-authenticate") {
                NotificationCenter.default.post(name: .showAccountReauth, object: nil)
                self.dismissCurrentAlert()
            },
            secondaryAction: EdgeCaseAlert.AlertAction(title: "Later") {
                self.dismissCurrentAlert()
            },
            severity: .warning
        )

        currentEdgeCaseAlert = alert
    }

    private func showPartialAuthenticationAlert(failedAccounts: Int) {
        let alert = EdgeCaseAlert(
            type: .authenticationExpired,
            title: "Some Accounts Need Re-authentication",
            message:
                "\(failedAccounts) of your accounts need to be re-authenticated. You can still view content from your other accounts.",
            primaryAction: EdgeCaseAlert.AlertAction(title: "Fix Accounts") {
                NotificationCenter.default.post(name: .showAccountReauth, object: nil)
                self.dismissCurrentAlert()
            },
            secondaryAction: EdgeCaseAlert.AlertAction(title: "Later") {
                self.dismissCurrentAlert()
            },
            severity: .info
        )

        currentEdgeCaseAlert = alert
    }

    private func dismissAlertIfType(_ type: EdgeCaseAlert.AlertType) {
        if currentEdgeCaseAlert?.type == type {
            currentEdgeCaseAlert = nil
        }
    }

    private func dismissCurrentAlert() {
        currentEdgeCaseAlert = nil
    }

    // MARK: - Recovery Actions

    private func checkNetworkAndRetry() {
        // Force a network path evaluation
        let path = networkMonitor.currentPath
        updateNetworkStatus(path)

        if networkStatus.isConnected {
            // Trigger a timeline refresh
            NotificationCenter.default.post(name: .retryNetworkOperations, object: nil)
            dismissCurrentAlert()
        }
    }

    private func performMemoryCleanup() {
        print("🧹 [EdgeCaseHandler] Performing memory cleanup")

        // Notify all components to clear their caches
        NotificationCenter.default.post(name: .performMemoryCleanup, object: nil)

        // Force garbage collection
        autoreleasepool {
            // This helps release any autoreleased objects
        }
    }

    // MARK: - Retry Logic

    func performRetryableOperation<T>(
        operation: @escaping () async throws -> T,
        maxAttempts: Int = Config.maxRetryAttempts,
        baseDelay: TimeInterval = Config.retryBaseDelay
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                print(
                    "🔄 [EdgeCaseHandler] Retry attempt \(attempt)/\(maxAttempts) failed: \(error.localizedDescription)"
                )

                // Don't retry on final attempt
                if attempt == maxAttempts {
                    break
                }

                // Check if error is retryable
                if !isRetryableError(error) {
                    print("🚫 [EdgeCaseHandler] Error is not retryable, aborting")
                    break
                }

                // Exponential backoff
                let delay = baseDelay * pow(2.0, Double(attempt - 1))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        // If we get here, all attempts failed
        throw lastError
            ?? NSError(
                domain: "EdgeCaseHandler", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "All retry attempts failed"])
    }

    private func isRetryableError(_ error: Error) -> Bool {
        // Network errors are generally retryable
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            case .badURL, .unsupportedURL, .cancelled:
                return false
            default:
                return true
            }
        }

        // HTTP errors
        if let httpError = error as NSError?, httpError.domain == "HTTP" {
            let statusCode = httpError.code
            // Retry on server errors, not client errors
            return statusCode >= 500
        }

        // Default to retryable for unknown errors
        return true
    }

    // MARK: - Public Interface

    /// Check if the app is in a state where it can perform network operations
    var canPerformNetworkOperations: Bool {
        return networkStatus.isConnected && memoryPressure != .critical
    }

    /// Get current system health status
    var systemHealthStatus: String {
        var status: [String] = []

        status.append("Network: \(networkStatus.userFriendlyDescription)")
        status.append("Memory: \(memoryPressure.userFriendlyDescription)")

        if authenticationState.needsUserAction {
            status.append("Auth: Needs attention")
        }

        return status.joined(separator: " • ")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let memoryPressureElevated = Notification.Name("memoryPressureElevated")
    static let memoryPressureCritical = Notification.Name("memoryPressureCritical")
    static let performMemoryCleanup = Notification.Name("performMemoryCleanup")
    static let retryNetworkOperations = Notification.Name("retryNetworkOperations")
    static let showAccountSetup = Notification.Name("showAccountSetup")
    static let showAccountReauth = Notification.Name("showAccountReauth")
}

// MARK: - Equatable Conformance

extension EdgeCaseHandler.NetworkStatus: Equatable {}
extension EdgeCaseHandler.MemoryPressureLevel: Equatable {}
extension EdgeCaseHandler.AuthenticationState: Equatable {
    static func == (
        lhs: EdgeCaseHandler.AuthenticationState, rhs: EdgeCaseHandler.AuthenticationState
    ) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown), (.authenticated, .authenticated),
            (.unauthenticated, .unauthenticated), (.expired, .expired):
            return true
        case (.partiallyAuthenticated(let lhsCount), .partiallyAuthenticated(let rhsCount)):
            return lhsCount == rhsCount
        default:
            return false
        }
    }
}

extension EdgeCaseHandler.EdgeCaseAlert.AlertType: Equatable {}
