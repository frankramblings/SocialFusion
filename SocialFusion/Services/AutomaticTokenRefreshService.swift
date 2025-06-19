import Combine
import Foundation
import UIKit
import UserNotifications
import os.log

/// Service that automatically refreshes tokens in the background to provide seamless authentication
@MainActor
public class AutomaticTokenRefreshService: ObservableObject {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.socialfusion", category: "AutomaticTokenRefresh")
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let socialServiceManager: SocialServiceManager

    // Refresh intervals
    private let checkInterval: TimeInterval = 300  // Check every 5 minutes
    private let refreshThreshold: TimeInterval = 3600  // Refresh if token expires within 1 hour

    // State tracking
    @Published public var isRefreshing = false
    @Published public var lastRefreshDate: Date?
    @Published public var refreshErrors: [String] = []
    @Published public var accountsNeedingReauth: [SocialAccount] = []

    // MARK: - Initialization

    public init(socialServiceManager: SocialServiceManager) {
        self.socialServiceManager = socialServiceManager
        logger.info("AutomaticTokenRefreshService initialized")
    }

    deinit {
        refreshTimer?.invalidate()
        refreshTimer = nil
        cancellables.removeAll()
    }

    // MARK: - Public Methods

    /// Start the automatic token refresh service
    public func startAutomaticRefresh() {
        logger.info("Starting automatic token refresh service")
        setupAutomaticRefresh()
    }

    /// Stop the automatic token refresh service
    public func stopAutomaticRefresh() async {
        logger.info("Stopping automatic token refresh service")
        refreshTimer?.invalidate()
        refreshTimer = nil
        cancellables.removeAll()
    }

    /// Manually trigger a refresh check for all accounts
    public func refreshAllTokensIfNeeded() async {
        guard !isRefreshing else {
            logger.info("Token refresh already in progress, skipping")
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        logger.info("Starting manual token refresh check")

        let allAccounts = socialServiceManager.accounts
        var refreshedCount = 0
        var errorCount = 0
        var accountsNeedingReauthList: [SocialAccount] = []

        for account in allAccounts {
            do {
                let wasRefreshed = try await refreshTokenIfNeeded(for: account)
                if wasRefreshed {
                    refreshedCount += 1
                    logger.info("Successfully refreshed token for \(account.username)")
                }
            } catch TokenRefreshError.noRefreshToken {
                // Special handling for accounts without refresh tokens
                accountsNeedingReauthList.append(account)
                let errorMessage =
                    "Account '\(account.username)' needs re-authentication (no refresh token available)"
                logger.warning("\(errorMessage)")
                refreshErrors.append(errorMessage)
                errorCount += 1

                // Show user notification for this specific issue
                showReauthenticationNotification(for: account)

            } catch {
                errorCount += 1
                let errorMessage =
                    "Failed to refresh token for \(account.username): \(error.localizedDescription)"
                logger.error("\(errorMessage)")
                refreshErrors.append(errorMessage)
            }
        }

        // Update accounts needing reauth
        accountsNeedingReauth = accountsNeedingReauthList

        // Keep only last 10 errors
        if refreshErrors.count > 10 {
            refreshErrors.removeFirst(refreshErrors.count - 10)
        }

        lastRefreshDate = Date()
        logger.info(
            "Token refresh check completed: \(refreshedCount) refreshed, \(errorCount) errors, \(accountsNeedingReauthList.count) need reauth"
        )

        // If there are accounts needing reauth, show a summary notification
        if !accountsNeedingReauthList.isEmpty {
            showReauthenticationSummaryNotification(accounts: accountsNeedingReauthList)
        }
    }

    /// Clear the reauth notification for a specific account (call when user re-adds the account)
    public func clearReauthNotification(for account: SocialAccount) {
        accountsNeedingReauth.removeAll { $0.id == account.id }
        logger.info("Cleared reauth notification for \(account.username)")
    }

    /// Get user-friendly error message for token refresh issues
    public func getTokenRefreshGuidance(for account: SocialAccount) -> String {
        switch account.platform {
        case .mastodon:
            if account.getRefreshToken() == nil {
                return
                    "Your Mastodon account '\(account.username)' was added using a manual token, which expires frequently. For the best experience, please remove and re-add this account using the OAuth login flow, which provides longer-lasting authentication."
            } else {
                return
                    "Your Mastodon account '\(account.username)' authentication has expired. Please remove and re-add the account to continue using it."
            }
        case .bluesky:
            if account.getRefreshToken() == nil {
                return
                    "Your Bluesky account '\(account.username)' needs to be re-authenticated. Please remove and re-add the account to continue using it."
            } else {
                return
                    "Your Bluesky account '\(account.username)' authentication has expired. Please remove and re-add the account to continue using it."
            }
        }
    }

    // MARK: - Private Methods

    private func setupAutomaticRefresh() {
        // Stop any existing timer
        refreshTimer?.invalidate()

        // Create a timer that checks tokens every 5 minutes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                await self?.refreshAllTokensIfNeeded()
            }
        }

        // Also refresh when app becomes active
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshAllTokensIfNeeded()
                }
            }
            .store(in: &cancellables)

        // Refresh when accounts change
        socialServiceManager.$accounts
            .dropFirst()  // Skip initial value
            .sink { [weak self] _ in
                Task { @MainActor in
                    // Small delay to let account setup complete
                    try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
                    await self?.refreshAllTokensIfNeeded()
                }
            }
            .store(in: &cancellables)

        logger.info("Automatic token refresh timer scheduled (interval: \(self.checkInterval)s)")
    }

    /// Check if a specific account's token needs refreshing and refresh it if needed
    /// - Parameter account: The account to check
    /// - Returns: True if the token was refreshed, false if no refresh was needed
    private func refreshTokenIfNeeded(for account: SocialAccount) async throws -> Bool {
        // Check if token needs refreshing (expires within the threshold)
        guard shouldRefreshToken(for: account) else {
            return false
        }

        logger.info("Token for \(account.username) needs refreshing")

        // Attempt to refresh based on platform
        switch account.platform {
        case .mastodon:
            return try await refreshMastodonToken(for: account)
        case .bluesky:
            return try await refreshBlueskyToken(for: account)
        }
    }

    /// Check if a token should be refreshed
    private func shouldRefreshToken(for account: SocialAccount) -> Bool {
        guard let expirationDate = account.tokenExpirationDate else {
            // No expiration date - assume token is still valid
            return false
        }

        // Refresh if token expires within the threshold (1 hour)
        let timeUntilExpiration = expirationDate.timeIntervalSinceNow
        return timeUntilExpiration <= refreshThreshold
    }

    /// Refresh a Mastodon token
    private func refreshMastodonToken(for account: SocialAccount) async throws -> Bool {
        guard account.getRefreshToken() != nil else {
            logger.warning("No refresh token available for Mastodon account \(account.username)")
            throw TokenRefreshError.noRefreshToken
        }

        let mastodonService = MastodonService()
        _ = try await mastodonService.refreshAccessToken(for: account)

        // Token was successfully refreshed
        logger.info("Successfully refreshed Mastodon token for \(account.username)")
        return true
    }

    /// Refresh a Bluesky token
    private func refreshBlueskyToken(for account: SocialAccount) async throws -> Bool {
        guard account.getRefreshToken() != nil else {
            logger.warning("No refresh token available for Bluesky account \(account.username)")
            throw TokenRefreshError.noRefreshToken
        }

        let blueskyService = BlueskyService()
        _ = try await blueskyService.refreshAccessToken(for: account)

        // Token was successfully refreshed
        logger.info("Successfully refreshed Bluesky token for \(account.username)")
        return true
    }

    /// Show a notification for a specific account needing reauth
    private func showReauthenticationNotification(for account: SocialAccount) {
        let content = UNMutableNotificationContent()
        content.title = "Account Authentication Needed"
        content.body =
            "Your \(account.platform.rawValue.capitalized) account '\(account.username)' needs to be re-authenticated for continued access."
        content.sound = .default
        content.categoryIdentifier = "REAUTH_NEEDED"

        let request = UNNotificationRequest(
            identifier: "reauth-\(account.id)",
            content: content,
            trigger: nil  // Show immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error(
                    "Failed to show reauth notification: \(error.localizedDescription)")
            }
        }
    }

    /// Show a summary notification when multiple accounts need reauth
    private func showReauthenticationSummaryNotification(accounts: [SocialAccount]) {
        guard accounts.count > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Multiple Accounts Need Authentication"
        content.body =
            "\(accounts.count) accounts need to be re-authenticated. Tap to manage your accounts."
        content.sound = .default
        content.categoryIdentifier = "MULTIPLE_REAUTH_NEEDED"

        let request = UNNotificationRequest(
            identifier: "multiple-reauth",
            content: content,
            trigger: nil  // Show immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error(
                    "Failed to show multiple reauth notification: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Background Task Support

extension AutomaticTokenRefreshService {

    /// Refresh tokens when app enters background (iOS 13+)
    public func handleAppDidEnterBackground() {
        logger.info("App entered background, scheduling token refresh")

        Task {
            await refreshAllTokensIfNeeded()
        }
    }

    /// Handle app will enter foreground
    public func handleAppWillEnterForeground() {
        logger.info("App will enter foreground, checking tokens")

        Task {
            await refreshAllTokensIfNeeded()
        }
    }
}

// MARK: - Error Types

public enum TokenRefreshError: Error, LocalizedError {
    case noRefreshToken
    case refreshFailed(String)
    case networkError(Error)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .noRefreshToken:
            return "No refresh token available"
        case .refreshFailed(let message):
            return "Token refresh failed: \(message)"
        case .networkError(let error):
            return "Network error during token refresh: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server during token refresh"
        }
    }
}
