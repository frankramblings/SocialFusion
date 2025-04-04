import SwiftUI

/// ProfileImageView displays a user's profile image with appropriate styling
/// based on their account type.
struct ProfileImageView: View {
    let account: SocialAccount

    @State private var refreshTrigger = false

    var body: some View {
        ZStack {
            // Colored circle for outline based on platform
            Circle()
                .fill(
                    account.platform == .mastodon ? Color("PrimaryColor") : Color("SecondaryColor")
                )
                .frame(width: 34, height: 34)

            // Profile image or initial
            if let imageURL = account.profileImageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())
                    } else if phase.error != nil {
                        // Show initial on error
                        InitialView(account: account)
                    } else {
                        // Show loading placeholder
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 30, height: 30)
                    }
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .onAppear {
                    print("Refreshing ProfileImageView for account: \(account.username)")
                }
                .onReceive(NotificationCenter.default.publisher(for: .profileImageUpdated)) {
                    notification in
                    if let accountId = notification.object as? String, accountId == account.id {
                        print("Received profile image update for \(account.username)")
                        refreshTrigger.toggle()
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
