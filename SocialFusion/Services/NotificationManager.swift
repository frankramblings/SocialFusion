import Foundation
import UserNotifications
import UIKit

class NotificationManager: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    static let shared = NotificationManager()
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ Notification authorization granted")
                self.setupNotificationCategories()
            } else if let error = error {
                print("❌ Notification authorization failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupNotificationCategories() {
        // Define actions for different platforms
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
        
        // Define categories
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
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .list, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier
        
        // Extract post/user info from userInfo
        // This would depend on how your server sends notifications
        
        if actionIdentifier == "REPLY_ACTION", let textResponse = response as? UNTextInputNotificationResponse {
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
        // Implement reply logic using SocialServiceManager
    }
    
    private func handleLike(userInfo: [AnyHashable: Any]) {
        print("❤️ Liking post from notification")
        // Implement like logic
    }
    
    private func handleRepost(userInfo: [AnyHashable: Any]) {
        print("🔁 Reposting from notification")
        // Implement repost logic
    }
    
    private func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        print("👉 Notification tapped")
        // Handle deep linking to the specific post/user
    }
}

