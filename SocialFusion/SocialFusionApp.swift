import AuthenticationServices
import BackgroundTasks
import Combine
import Foundation
import SwiftUI
import UIKit

@main
struct SocialFusionApp: App {
    // Create a single instance for the app
    @StateObject private var serviceManager = SocialServiceManager()

    // Version manager for launch animation control
    @StateObject private var appVersionManager = AppVersionManager()

    // OAuth manager for handling authentication callbacks
    @StateObject private var oauthManager = OAuthManager()

    // Navigation environment for deep linking
    @StateObject private var navigationEnvironment = PostNavigationEnvironment()

    // Notification manager for rich notifications
    @StateObject private var notificationManager = NotificationManager.shared

    // Edge case handler for beta readiness
    @StateObject private var edgeCaseHandler = EdgeCaseHandler.shared

    // Draft store for saving unfinished posts
    @StateObject private var draftStore = DraftStore()

    // Chat stream service for real-time messaging
    @StateObject private var chatStreamService = ChatStreamService()

    @AppStorage("Onboarding.Completed") private var hasCompletedOnboarding = false

    // Environment object for scene phase to detect when app is terminating
    @Environment(\.scenePhase) private var scenePhase

    // App background state observer
    private let willResignActivePublisher = NotificationCenter.default.publisher(
        for: UIApplication.willResignActiveNotification)

    // App termination observer
    private let willTerminatePublisher = NotificationCenter.default.publisher(
        for: UIApplication.willTerminateNotification)

    var body: some Scene {
        WindowGroup {
            if appVersionManager.shouldShowLaunchAnimation {
                LaunchAnimationView {
                    // Animation completed, show main content
                    withAnimation(.easeOut(duration: 0.5)) {
                        appVersionManager.markLaunchAnimationCompleted()
                    }
                }
                .environmentObject(serviceManager)
                .environmentObject(appVersionManager)
                .environmentObject(oauthManager)
                .environmentObject(navigationEnvironment)
                .environmentObject(draftStore)
                .environmentObject(edgeCaseHandler)
                .environmentObject(chatStreamService)
                .enableLiquidGlass()
                .onOpenURL { url in
                    handleURL(url)
                }
            } else if serviceManager.accounts.isEmpty && !hasCompletedOnboarding {
                OnboardingView()
                    .environmentObject(serviceManager)
                    .environmentObject(appVersionManager)
                    .environmentObject(oauthManager)
                    .environmentObject(navigationEnvironment)
                    .environmentObject(draftStore)
                    .environmentObject(edgeCaseHandler)
                    .environmentObject(chatStreamService)
                    .enableLiquidGlass()
            } else {
                ContentView()
                    .environmentObject(serviceManager)
                    .environmentObject(appVersionManager)
                    .environmentObject(oauthManager)
                    .environmentObject(navigationEnvironment)
                    .environmentObject(notificationManager)
                    .environmentObject(draftStore)
                    .environmentObject(edgeCaseHandler)
                    .environmentObject(chatStreamService)
                    .enableLiquidGlass()
                    .onAppear {
                        notificationManager.serviceManager = serviceManager
                        notificationManager.registerBackgroundTask()
                        if UserDefaults.standard.bool(forKey: "enableNotifications") {
                            notificationManager.scheduleBackgroundRefresh()
                            Task {
                                await notificationManager.pollAndDeliverNotifications()
                            }
                        }
                        chatStreamService.configure(
                            mastodonService: serviceManager.mastodonService,
                            blueskyService: serviceManager.blueskyService
                        )
                    }
                    .onOpenURL { url in
                        handleURL(url)
                    }
            }
        }
    }

    private func handleURL(_ url: URL) {
        // Handle OAuth callback URLs
        if url.scheme == "socialfusion" && url.host == "oauth" {
            print("Received OAuth callback URL: \(url)")
            handleOAuthCallback(url: url)
        } else {
            print("Received deep link or universal link: \(url)")
            navigationEnvironment.handleDeepLink(url, serviceManager: serviceManager)
        }
    }

    private func handleOAuthCallback(url: URL) {
        // Forward the callback to the OAuth manager
        oauthManager.handleCallback(url: url)
    }

    private func checkForAutofillRecovery() {
        // Check if AddAccountView was presented when going to background
        let wasPresented = UserDefaults.standard.bool(
            forKey: "AddAccountView.WasPresentedDuringBackground")

        if wasPresented {
            // Add a flag to prevent multiple handlers from responding simultaneously
            UserDefaults.standard.set(true, forKey: "AddAccountView.RecoveryInProgress")

            // Small delay to ensure the app is fully active
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
                NotificationCenter.default.post(
                    name: Notification.Name("shouldRepresentAddAccount"), object: nil,
                    userInfo: [
                        "source": "autofillRecovery"
                    ]
                )

                // Clear the flag
                UserDefaults.standard.removeObject(
                    forKey: "AddAccountView.WasPresentedDuringBackground")
            }
        }
    }

    // MARK: - Testing Support

    /// Check if app is in testing mode
    private var isTestingMode: Bool {
        #if DEBUG
            // Check for debug setting
            if UserDefaults.standard.bool(forKey: "ArchitectureTestingEnabled") {
                return true
            }

            // Check for command line arguments
            if ProcessInfo.processInfo.arguments.contains("--test-architecture") {
                return true
            }

            // Check for environment variable
            if ProcessInfo.processInfo.environment["SOCIALFUSION_TEST_MODE"] == "1" {
                return true
            }
        #endif

        return false
    }
}
