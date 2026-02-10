import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

class NotificationManager: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
  static let shared = NotificationManager()
  static let bgTaskIdentifier = "com.socialfusion.notification-refresh"

  private let provider: NotificationProvider = PollingNotificationProvider()
  private let deliveredIdsKey = "NotificationManager.deliveredIds"

  weak var serviceManager: SocialServiceManager?

  /// IDs of notifications already delivered as local notifications
  private var deliveredIds: Set<String> {
    get {
      Set(UserDefaults.standard.stringArray(forKey: deliveredIdsKey) ?? [])
    }
    set {
      // Keep only last 500 to prevent unbounded growth
      let trimmed = Array(newValue.suffix(500))
      UserDefaults.standard.set(trimmed, forKey: deliveredIdsKey)
    }
  }

  override init() {
    super.init()
    UNUserNotificationCenter.current().delegate = self
  }

  func requestAuthorization() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
      granted, error in
      if granted {
        print("✅ Notification authorization granted")
        self.setupNotificationCategories()
      } else if let error = error {
        print("❌ Notification authorization failed: \(error.localizedDescription)")
      }
    }
  }

  func setupNotificationCategories() {
    let replyAction = UNTextInputNotificationAction(
      identifier: "REPLY_ACTION",
      title: "Reply",
      options: [],
      textInputButtonTitle: "Send",
      textInputPlaceholder: "Type your reply..."
    )

    let likeAction = UNNotificationAction(
      identifier: "LIKE_ACTION",
      title: "Like",
      options: []
    )

    let repostAction = UNNotificationAction(
      identifier: "REPOST_ACTION",
      title: "Repost",
      options: []
    )

    let postCategory = UNNotificationCategory(
      identifier: "POST_NOTIFICATION",
      actions: [replyAction, likeAction, repostAction],
      intentIdentifiers: [],
      options: [.customDismissAction]
    )

    let dmCategory = UNNotificationCategory(
      identifier: "DM_NOTIFICATION",
      actions: [replyAction],
      intentIdentifiers: [],
      options: [.allowInCarPlay]
    )

    UNUserNotificationCenter.current().setNotificationCategories([postCategory, dmCategory])
  }

  // MARK: - Background Refresh

  func registerBackgroundTask() {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.bgTaskIdentifier,
      using: nil
    ) { [weak self] task in
      self?.handleBackgroundRefresh(task as! BGAppRefreshTask)
    }
  }

  func scheduleBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)  // 15 min
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      print("❌ Failed to schedule background refresh: \(error)")
    }
  }

  private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
    // Schedule the next refresh immediately
    scheduleBackgroundRefresh()

    let workTask = Task {
      await pollAndDeliverNotifications()
    }

    task.expirationHandler = {
      workTask.cancel()
    }

    Task {
      _ = await workTask.result
      task.setTaskCompleted(success: !workTask.isCancelled)
    }
  }

  /// Polls for new notifications and delivers them as local notifications.
  /// Called from background refresh and can also be called from foreground.
  @MainActor
  func pollAndDeliverNotifications() async {
    guard let serviceManager = self.serviceManager else { return }
    guard UserDefaults.standard.bool(forKey: "enableNotifications") else { return }

    do {
      let notifications = try await provider.fetchNewNotifications(using: serviceManager)
      var currentDelivered = deliveredIds

      for notification in notifications {
        let dedupKey = "\(notification.id)"
        guard !currentDelivered.contains(dedupKey) else { continue }

        // Check per-type settings
        guard isTypeEnabled(notification.type) else { continue }

        deliverLocalNotification(notification)
        currentDelivered.insert(dedupKey)
      }

      deliveredIds = currentDelivered
    } catch {
      print("❌ Failed to poll notifications: \(error)")
    }
  }

  private func isTypeEnabled(_ type: AppNotification.NotificationType) -> Bool {
    switch type {
    case .mention:
      return UserDefaults.standard.object(forKey: "notifyMentions") as? Bool ?? true
    case .like:
      return UserDefaults.standard.object(forKey: "notifyLikes") as? Bool ?? true
    case .repost:
      return UserDefaults.standard.object(forKey: "notifyReposts") as? Bool ?? true
    case .follow:
      return UserDefaults.standard.object(forKey: "notifyFollows") as? Bool ?? true
    case .poll, .update:
      return true
    }
  }

  private func deliverLocalNotification(_ notification: AppNotification) {
    let content = UNMutableNotificationContent()

    let displayName =
      notification.fromAccount.displayName ?? notification.fromAccount.username

    switch notification.type {
    case .mention:
      content.title = "@\(notification.fromAccount.username) mentioned you"
      content.categoryIdentifier = "POST_NOTIFICATION"
    case .like:
      content.title = "\(displayName) liked your post"
    case .repost:
      content.title = "\(displayName) reposted your post"
    case .follow:
      content.title = "\(displayName) followed you"
    case .poll:
      content.title = "A poll you voted in has ended"
    case .update:
      content.title = "\(displayName) edited a post"
    }

    // Body: post excerpt if available
    if let post = notification.post {
      let plainText = post.content.replacingOccurrences(
        of: "<[^>]+>", with: "", options: .regularExpression)
      content.body = String(plainText.prefix(140))
    }

    content.sound = .default
    content.threadIdentifier = notification.account.id  // Group by account

    // Store info for action handlers
    content.userInfo = [
      "accountId": notification.account.id,
      "platform": notification.account.platform.rawValue,
      "postId": notification.post?.id ?? "",
      "platformSpecificId": notification.post?.platformSpecificId ?? "",
      "cid": notification.post?.cid ?? "",
      "notificationType": notification.type.rawValue,
      "fromUsername": notification.fromAccount.username,
    ]

    let request = UNNotificationRequest(
      identifier: "socialfusion-\(notification.id)",
      content: content,
      trigger: nil  // Deliver immediately
    )

    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        print("❌ Failed to deliver notification: \(error)")
      }
    }
  }

  // MARK: - UNUserNotificationCenterDelegate

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    let typeRaw = userInfo["notificationType"] as? String ?? ""
    let notificationType = AppNotification.NotificationType(rawValue: typeRaw)

    // Check if user is on the notifications tab
    let isOnNotificationsTab = isViewingNotificationsTab()

    if isOnNotificationsTab {
      // Suppress banner, the list will refresh
      completionHandler([])
    } else if notificationType == .mention {
      // Show toast for mentions
      let title = notification.request.content.title
      let body = notification.request.content.body
      Task { @MainActor in
        ToastManager.shared.show("\(title): \(body)", duration: 4.0)
      }
      completionHandler([.badge, .sound])
    } else {
      // Likes, reposts, follows — badge only
      completionHandler([.badge])
    }
  }

  private func isViewingNotificationsTab() -> Bool {
    // ContentView tracks selectedTab: 0=Home, 1=Notifications, 2=Messages, 3=Search, 4=Profile
    // We check via a shared UserDefaults key that ContentView updates
    return UserDefaults.standard.integer(forKey: "currentSelectedTab") == 1
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    let actionIdentifier = response.actionIdentifier

    if actionIdentifier == "REPLY_ACTION",
      let textResponse = response as? UNTextInputNotificationResponse
    {
      let replyText = textResponse.userText
      handleReply(replyText: replyText, userInfo: userInfo)
    } else if actionIdentifier == "LIKE_ACTION" {
      handleLike(userInfo: userInfo)
    } else if actionIdentifier == "REPOST_ACTION" {
      handleRepost(userInfo: userInfo)
    } else {
      // Default action (tapping the notification)
      handleNotificationTap(userInfo: userInfo)
    }

    completionHandler()
  }

  // MARK: - Handlers

  private func handleReply(replyText: String, userInfo: [AnyHashable: Any]) {
    guard let accountId = userInfo["accountId"] as? String,
      let platformRaw = userInfo["platform"] as? String,
      let platformSpecificId = userInfo["platformSpecificId"] as? String,
      !platformSpecificId.isEmpty,
      !replyText.isEmpty
    else { return }

    Task { @MainActor in
      guard let serviceManager = self.serviceManager,
        let account = serviceManager.accounts.first(where: { $0.id == accountId })
      else { return }

      do {
        let platform = SocialPlatform(rawValue: platformRaw)
        if platform == .mastodon {
          try await mastodonReply(
            statusId: platformSpecificId, content: replyText, account: account)
        } else if platform == .bluesky {
          let cid = userInfo["cid"] as? String ?? ""
          try await blueskyReply(
            uri: platformSpecificId, cid: cid, content: replyText, account: account)
        }
      } catch {
        let errorContent = UNMutableNotificationContent()
        errorContent.title = "Reply failed"
        errorContent.body = "Tap to open the app and try again."
        errorContent.sound = .default
        let request = UNNotificationRequest(
          identifier: "reply-error-\(UUID().uuidString)",
          content: errorContent,
          trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
      }
    }
  }

  private func handleLike(userInfo: [AnyHashable: Any]) {
    guard let accountId = userInfo["accountId"] as? String,
      let platformRaw = userInfo["platform"] as? String,
      let platformSpecificId = userInfo["platformSpecificId"] as? String,
      !platformSpecificId.isEmpty
    else { return }

    Task { @MainActor in
      guard let serviceManager = self.serviceManager,
        let account = serviceManager.accounts.first(where: { $0.id == accountId })
      else { return }

      do {
        let platform = SocialPlatform(rawValue: platformRaw)
        if platform == .mastodon {
          try await mastodonLike(statusId: platformSpecificId, account: account)
        } else if platform == .bluesky {
          let cid = userInfo["cid"] as? String ?? ""
          try await blueskyLike(uri: platformSpecificId, cid: cid, account: account)
        }
      } catch {
        print("❌ Like from notification failed: \(error)")
      }
    }
  }

  private func handleRepost(userInfo: [AnyHashable: Any]) {
    guard let accountId = userInfo["accountId"] as? String,
      let platformRaw = userInfo["platform"] as? String,
      let platformSpecificId = userInfo["platformSpecificId"] as? String,
      !platformSpecificId.isEmpty
    else { return }

    Task { @MainActor in
      guard let serviceManager = self.serviceManager,
        let account = serviceManager.accounts.first(where: { $0.id == accountId })
      else { return }

      do {
        let platform = SocialPlatform(rawValue: platformRaw)
        if platform == .mastodon {
          try await mastodonRepost(statusId: platformSpecificId, account: account)
        } else if platform == .bluesky {
          let cid = userInfo["cid"] as? String ?? ""
          try await blueskyRepost(uri: platformSpecificId, cid: cid, account: account)
        }
      } catch {
        print("❌ Repost from notification failed: \(error)")
      }
    }
  }

  private func handleNotificationTap(userInfo: [AnyHashable: Any]) {
    guard let postId = userInfo["postId"] as? String else { return }

    Task { @MainActor in
      if !postId.isEmpty {
        NotificationCenter.default.post(
          name: Notification.Name("navigateToPost"),
          object: nil,
          userInfo: ["postId": postId]
        )
      }
    }
  }

  // MARK: - Mastodon API Calls

  private func mastodonLike(statusId: String, account: SocialAccount) async throws {
    let serverUrl = formatMastodonServerURL(account)
    guard let url = URL(string: "\(serverUrl)/api/v1/statuses/\(statusId)/favourite") else {
      return
    }
    let request = try await makeAuthenticatedRequest(url: url, method: "POST", account: account)
    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw NSError(domain: "NotificationManager", code: -1)
    }
  }

  private func mastodonRepost(statusId: String, account: SocialAccount) async throws {
    let serverUrl = formatMastodonServerURL(account)
    guard let url = URL(string: "\(serverUrl)/api/v1/statuses/\(statusId)/reblog") else { return }
    let request = try await makeAuthenticatedRequest(url: url, method: "POST", account: account)
    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw NSError(domain: "NotificationManager", code: -1)
    }
  }

  private func mastodonReply(
    statusId: String, content: String, account: SocialAccount
  ) async throws {
    let serverUrl = formatMastodonServerURL(account)
    guard let url = URL(string: "\(serverUrl)/api/v1/statuses") else { return }
    let body: [String: Any] = ["status": content, "in_reply_to_id": statusId]
    var request = try await makeAuthenticatedRequest(url: url, method: "POST", account: account)
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      throw NSError(domain: "NotificationManager", code: -1)
    }
  }

  // MARK: - Bluesky API Calls

  private func blueskyLike(uri: String, cid: String, account: SocialAccount) async throws {
    guard !cid.isEmpty else { return }
    let serverUrl = formatBlueskyServerURL(account)
    guard let url = URL(string: "\(serverUrl)/xrpc/com.atproto.repo.createRecord") else { return }
    let body: [String: Any] = [
      "repo": account.username,
      "collection": "app.bsky.feed.like",
      "record": [
        "$type": "app.bsky.feed.like",
        "subject": ["uri": uri, "cid": cid],
        "createdAt": ISO8601DateFormatter().string(from: Date()),
      ],
    ]
    var request = try await makeAuthenticatedRequest(url: url, method: "POST", account: account)
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw NSError(domain: "NotificationManager", code: -1)
    }
  }

  private func blueskyRepost(uri: String, cid: String, account: SocialAccount) async throws {
    guard !cid.isEmpty else { return }
    let serverUrl = formatBlueskyServerURL(account)
    guard let url = URL(string: "\(serverUrl)/xrpc/com.atproto.repo.createRecord") else { return }
    let body: [String: Any] = [
      "repo": account.username,
      "collection": "app.bsky.feed.repost",
      "record": [
        "$type": "app.bsky.feed.repost",
        "subject": ["uri": uri, "cid": cid],
        "createdAt": ISO8601DateFormatter().string(from: Date()),
      ],
    ]
    var request = try await makeAuthenticatedRequest(url: url, method: "POST", account: account)
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw NSError(domain: "NotificationManager", code: -1)
    }
  }

  private func blueskyReply(
    uri: String, cid: String, content: String, account: SocialAccount
  ) async throws {
    guard !cid.isEmpty else { return }
    let serverUrl = formatBlueskyServerURL(account)
    guard let url = URL(string: "\(serverUrl)/xrpc/com.atproto.repo.createRecord") else { return }
    let body: [String: Any] = [
      "repo": account.username,
      "collection": "app.bsky.feed.post",
      "record": [
        "$type": "app.bsky.feed.post",
        "text": content,
        "reply": [
          "root": ["uri": uri, "cid": cid],
          "parent": ["uri": uri, "cid": cid],
        ],
        "createdAt": ISO8601DateFormatter().string(from: Date()),
      ],
    ]
    var request = try await makeAuthenticatedRequest(url: url, method: "POST", account: account)
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw NSError(domain: "NotificationManager", code: -1)
    }
  }

  // MARK: - Helpers

  private func makeAuthenticatedRequest(
    url: URL, method: String, account: SocialAccount
  ) async throws -> URLRequest {
    let token = try await account.getValidAccessToken()
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    return request
  }

  private func formatMastodonServerURL(_ account: SocialAccount) -> String {
    let raw = account.serverURL?.absoluteString ?? "https://mastodon.social"
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if trimmed.isEmpty { return "https://mastodon.social" }
    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
      // Strip trailing slash
      return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }
    return "https://\(trimmed)"
  }

  private func formatBlueskyServerURL(_ account: SocialAccount) -> String {
    let raw = account.serverURL?.absoluteString ?? "bsky.social"
    let sanitized = raw.replacingOccurrences(of: "https://", with: "")
      .replacingOccurrences(of: "http://", with: "")
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return "https://\(sanitized.isEmpty ? "bsky.social" : sanitized)"
  }
}
