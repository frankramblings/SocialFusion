import AuthenticationServices
import Combine
import Foundation
import SwiftUI
import UIKit

@main
struct SocialFusionApp: App {
    // Use StateObject for SocialServiceManager since we're creating it here
    @StateObject private var socialServiceManager = SocialServiceManager()

    // Environment object for scene phase to detect when app is terminating
    @Environment(\.scenePhase) private var scenePhase

    // App background state observer
    private let willResignActivePublisher = NotificationCenter.default.publisher(
        for: UIApplication.willResignActiveNotification)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(socialServiceManager)
                .onOpenURL { url in
                    // Handle OAuth callback URLs
                    if url.scheme == "socialfusion" {
                        print("Received callback URL: \(url)")
                        // In the future, we'll implement callback handling through SocialServiceManager
                        // Example: socialServiceManager.handleOAuthCallback(url: url)
                    }
                }
                // Use NotificationCenter instead of onChange for backward compatibility
                .onReceive(willResignActivePublisher) { _ in
                    // App is going to background, save account data
                    Task {
                        await socialServiceManager.saveAllAccounts()
                    }
                }
        }
    }
}
