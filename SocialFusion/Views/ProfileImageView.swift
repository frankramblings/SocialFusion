import SwiftUI

/// ProfileImageView displays a user's profile image with appropriate styling
/// based on their account type.
public struct ProfileImageView: View {
    let account: SocialAccount

    @State private var refreshTrigger = false

    public var body: some View {
        ZStack {
            // Colored circle for outline based on platform.
            // Routes through SocialPlatform.swiftUIColor — single
            // source of truth (86a7ca5). Color("PrimaryColor") /
            // Color("SecondaryColor") asset references conflict
            // with SwiftUI's built-in .primary / .secondary
            // semantics and surface build warnings.
            Circle()
                .fill(account.platform.swiftUIColor)
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
                    // Initials while the image is loading — same identity
                    // as the no-URL InitialView branch, so the avatar
                    // doesn't flash between spinner and letter.
                    InitialView(account: account)
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .id(imageURL.absoluteString)
                .onAppear {
                    #if DEBUG
                    print(
                        "👁️ [ProfileImageView] Profile image appeared for account: \(account.username)"
                    )
                    #endif
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
                        #if DEBUG
                        print(
                            "🔄 [ProfileImageView] Received profile image update for \(account.username)"
                        )
                        #endif
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let name = account.displayName ?? account.username
        return "Profile picture for \(name), on \(account.platform.accessibilityLabel)"
    }
}

/// Displays the user's initial when no profile image is available
struct InitialView: View {
    let account: SocialAccount

    var body: some View {
        Text(String((account.displayName ?? account.username).prefix(1)))
            .font(.system(size: 14, weight: .bold))
            // Initial color = brand color via swiftUIColor.
            // (Was Color("PrimaryColor") / Color("SecondaryColor"),
            // the asset-catalog references that conflict with
            // SwiftUI's `.primary` / `.secondary` semantics.)
            .foregroundColor(account.platform.swiftUIColor)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.white))
    }
}
