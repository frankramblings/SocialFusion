import AuthenticationServices
import Combine
import Foundation
import SwiftUI
import UIKit

@main
struct SocialFusionApp: App {
    // Use the shared singleton instead of creating a new instance
    @StateObject private var socialServiceManager = SocialServiceManager.shared

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
                .environmentObject(socialServiceManager)
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
                    // App is going to background - trigger account saving
                    print("App entering background - saving accounts")
                    socialServiceManager.saveAccounts()
                }
                .onReceive(willTerminatePublisher) { _ in
                    // App is terminating - ensure accounts are saved
                    print("App terminating - final account save")
                    socialServiceManager.saveAccounts()
                }
                .onChange(of: scenePhase) { _ in
                    if scenePhase == .background || scenePhase == .inactive {
                        // App is entering background - save state
                        print("Scene phase changed to \(scenePhase) - saving app state")
                        socialServiceManager.saveAccounts()
                    } else if scenePhase == .active {
                        // App returned to foreground - check if AddAccountView needs to be re-presented
                        checkForAutofillRecovery()
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
            print(
                "🔐 [SocialFusionApp] Detected AddAccountView was dismissed during autofill - posting recovery notification"
            )

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
}
