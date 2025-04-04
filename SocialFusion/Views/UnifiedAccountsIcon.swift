import SwiftUI

struct UnifiedAccountsIcon: View {
    let mastodonAccounts: [SocialAccount]
    let blueskyAccounts: [SocialAccount]

    @State private var refreshTrigger = false

    var body: some View {
        ZStack {
            // Background circle (gray)
            Circle()
                .fill(Color.gray.opacity(0.1))
                .frame(width: 36, height: 36)
                .onAppear {
                    print(
                        "UnifiedAccountsIcon appeared with \(mastodonAccounts.count) Mastodon accounts and \(blueskyAccounts.count) Bluesky accounts"
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: .profileImageUpdated)) {
                    notification in
                    if let accountId = notification.object as? String {
                        // Check if the updated account is one of ours
                        let isOurAccount =
                            mastodonAccounts.contains { $0.id == accountId }
                            || blueskyAccounts.contains { $0.id == accountId }
                        if isOurAccount {
                            print("Refreshing UnifiedAccountsIcon for account update: \(accountId)")
                            refreshTrigger.toggle()
                        }
                    }
                }

            if mastodonAccounts.isEmpty && blueskyAccounts.isEmpty {
                // No accounts, show a placeholder
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
            } else {
                // Show account profiles with colored outlines
                ZStack {
                    // First profile (if any Mastodon accounts)
                    if let firstMastodonAccount = mastodonAccounts.first {
                        ProfileImageView(account: firstMastodonAccount)
                            .offset(x: -6, y: -6)
                    }

                    // Second profile (if any Bluesky accounts)
                    if let firstBlueskyAccount = blueskyAccounts.first {
                        ProfileImageView(account: firstBlueskyAccount)
                            .offset(x: 6, y: 6)
                    }
                }
            }
        }
        .id(refreshTrigger)  // Force view refresh when trigger changes
    }
}
