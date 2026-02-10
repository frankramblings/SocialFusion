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
    print("💬 Replying with: \(replyText)")
    // TODO: Implement reply logic using SocialServiceManager (Task 6)
  }

  private func handleLike(userInfo: [AnyHashable: Any]) {
    print("❤️ Liking post from notification")
    // TODO: Implement like logic (Task 6)
  }

  private func handleRepost(userInfo: [AnyHashable: Any]) {
    print("🔁 Reposting from notification")
    // TODO: Implement repost logic (Task 6)
  }

  private func handleNotificationTap(userInfo: [AnyHashable: Any]) {
    print("👉 Notification tapped")
    // TODO: Implement deep linking (Task 6)
  }
}
