import AuthenticationServices
import Combine
import Foundation
import SwiftUI
import UIKit

@main
struct SocialFusionApp: App {
    // Use the shared singleton instead of creating a new instance
    @StateObject private var serviceManager = SocialServiceManager.shared

    // Version manager for launch animation control
    @StateObject private var appVersionManager = AppVersionManager()

    // OAuth manager for handling authentication callbacks
    @StateObject private var oauthManager = OAuthManager()

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
            ContentView()
                .environmentObject(serviceManager)
                .environmentObject(appVersionManager)
                .environmentObject(oauthManager)
                .onOpenURL { url in
                    // Handle OAuth callback URLs
                    if url.scheme == "socialfusion" {
                        print("Received OAuth callback URL: \(url)")
                        // Handle the OAuth callback
                        handleOAuthCallback(url: url)
                    }
                }
                // Use NotificationCenter instead of onChange for backward compatibility
                .onReceive(willResignActivePublisher) { _ in
                    // PHASE 3+: Removed state modification to prevent AttributeGraph cycles
                    // Account saving will be handled through normal app lifecycle instead
                }
                .onReceive(willTerminatePublisher) { _ in
                    // PHASE 3+: Removed state modification to prevent AttributeGraph cycles
                    // Account saving will be handled through normal app lifecycle instead
                }
                .onChange(of: scenePhase) { _ in
                    // PHASE 3+: Removed state modifications to prevent AttributeGraph cycles
                    // App state management will be handled through normal lifecycle instead
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didBecomeActiveNotification)
                ) { _ in
                    // Ensure timeline refreshes when app becomes active
                    Task {
                        await serviceManager.ensureTimelineRefresh()
                    }
                }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
