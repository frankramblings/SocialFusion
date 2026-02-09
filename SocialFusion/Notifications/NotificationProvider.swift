import Foundation

/// Protocol abstracting notification fetching. Beta uses polling; future uses APNS relay.
protocol NotificationProvider {
  func fetchNewNotifications(using serviceManager: SocialServiceManager) async throws -> [AppNotification]
}

/// Beta implementation: calls Mastodon/Bluesky APIs directly via SocialServiceManager.
final class PollingNotificationProvider: NotificationProvider {
  func fetchNewNotifications(using serviceManager: SocialServiceManager) async throws -> [AppNotification] {
    try await serviceManager.fetchNotifications()
  }
}
