import AuthenticationServices
import Combine
// Import our authentication manager
import Foundation
import SwiftUI
import UIKit

// Add direct import for the Services directory files
@main
struct SocialFusionApp: App {
    // Create a temporary stub for AuthenticationManager just to get the app to build
    class TempAuthManager: ObservableObject {
        static let shared = TempAuthManager()
        func handleCallback(url: URL) {}
    }

    @StateObject private var socialServiceManager = SocialServiceManager()
    @StateObject private var authManager = TempAuthManager.shared

    // Environment object for scene phase to detect when app is terminating
    @Environment(\.scenePhase) private var scenePhase

    // App background state observer
    private let willResignActivePublisher = NotificationCenter.default.publisher(
        for: UIApplication.willResignActiveNotification)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(socialServiceManager)
                .environmentObject(authManager)
                .onOpenURL { url in
                    // Handle OAuth callback URLs
                    if url.scheme == "socialfusion" {
                        print("Received callback URL: \(url)")
                        // In the future, we'll implement callback handling through SocialServiceManager
                        // Example: socialServiceManager.handleOAuthCallback(url: url)
                        authManager.handleCallback(url: url)
                    }
                }
                // Use NotificationCenter instead of onChange for backward compatibility
                .onReceive(willResignActivePublisher) { _ in
                    // App is going to background, save account data
                    socialServiceManager.saveAllAccounts()
                }
        }
    }
}
