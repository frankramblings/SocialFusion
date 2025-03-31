import Foundation
import SwiftUI

// Define a typealias for the OAuthManager to help with compilation
typealias OAuthManager = SocialFusion.Services.OAuthManager

@main
struct SocialFusionApp: App {
    @StateObject private var socialServiceManager = SocialServiceManager()
    @StateObject private var oauthManager = Services.OAuthManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(socialServiceManager)
                .environmentObject(oauthManager)
                .onOpenURL { url in
                    // Handle OAuth callback URLs
                    if url.scheme == "socialfusion" {
                        oauthManager.handleCallback(url: url)
                    }
                }
        }
    }
}
