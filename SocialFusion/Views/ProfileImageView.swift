import SwiftUI

/// ProfileImageView displays a user's profile image with appropriate styling
/// based on their account type.
public struct ProfileImageView: View {
    let account: SocialAccount

    @State private var refreshTrigger = false

    public var body: some View {
        ZStack {
            // Colored circle for outline based on platform
            Circle()
                .fill(
                    account.platform == .mastodon ? Color("PrimaryColor") : Color("SecondaryColor")
                )
                .frame(width: 34, height: 34)

            // Profile image or initial
            if let imageURL = account.profileImageURL {
                CachedAsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 30, height: 30)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.6)
                        )
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .id(imageURL.absoluteString)
                .onAppear {
                    print(
                        "👁️ [ProfileImageView] Profile image appeared for account: \(account.username)"
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: .profileImageUpdated)) {
                    notification in
                    // Check if this notification is for this specific account
                    let shouldRefresh =
                        if let updatedAccount = notification.object as? SocialAccount {
                            updatedAccount.id == account.id
                        } else if let accountId = notification.userInfo?["accountId"] as? String {
                            accountId == account.id
                        } else {
                            false
                        }

                    if shouldRefresh {
                        print(
                            "🔄 [ProfileImageView] Received profile image update for \(account.username)"
                        )
                        // Use Task to defer state update outside of view update cycle
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                            refreshTrigger.toggle()
                        }
                    }
                }
            } else {
                // No URL, show initial
                InitialView(account: account)
            }
        }
        .id(refreshTrigger)  // Force view refresh when trigger changes
    }
}

/// Displays the user's initial when no profile image is available
struct InitialView: View {
    let account: SocialAccount

    var body: some View {
        Text(String((account.displayName ?? account.username).prefix(1)))
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(
                account.platform == .mastodon ? Color("PrimaryColor") : Color("SecondaryColor")
            )
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.white))
    }
}
