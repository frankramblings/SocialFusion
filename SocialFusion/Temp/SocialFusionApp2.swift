import Foundation
import SwiftUI

@main
struct SocialFusionApp: App {
    @StateObject private var socialServiceManager = SocialServiceManager()
    @StateObject private var oauthManager = OAuthManager()

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
