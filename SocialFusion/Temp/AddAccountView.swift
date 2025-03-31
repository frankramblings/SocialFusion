import Foundation
import SwiftUI

struct AddAccountView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @EnvironmentObject private var oauthManager: OAuthManager
    @Environment(\.presentationMode) var presentationMode

    @State private var selectedPlatform: SocialPlatform = .mastodon
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Platform")) {
                    HStack(spacing: 10) {
                        PlatformButton(
                            platform: .mastodon,
                            isSelected: selectedPlatform == .mastodon,
                            action: { selectedPlatform = .mastodon }
                        )

                        PlatformButton(
                            platform: .bluesky,
                            isSelected: selectedPlatform == .bluesky,
                            action: { selectedPlatform = .bluesky }
                        )
                    }
                    .onChange(of: selectedPlatform) { _ in
                        // Clear any error when platform changes
                        errorMessage = ""

                        // Set default server for Bluesky or clear for Mastodon
                        if selectedPlatform == .bluesky {
                            server = "bsky.social"
                        } else {
                            server = ""
                        }
                    }
                }

                // Rest of the view implementation...
            }
        }
    }

    // Rest of the implementation...
}
