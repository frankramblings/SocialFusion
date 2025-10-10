import SwiftUI

public struct UnifiedAccountsIcon: View {
    let mastodonAccounts: [SocialAccount]
    let blueskyAccounts: [SocialAccount]

    @State private var refreshTrigger = false
    @Environment(\.colorScheme) var colorScheme

    public init(mastodonAccounts: [SocialAccount], blueskyAccounts: [SocialAccount]) {
        self.mastodonAccounts = mastodonAccounts
        self.blueskyAccounts = blueskyAccounts
    }

    private var totalAccountCount: Int {
        mastodonAccounts.count + blueskyAccounts.count
    }

    private var hasAccounts: Bool {
        !mastodonAccounts.isEmpty || !blueskyAccounts.isEmpty
    }

    public var body: some View {
        ZStack {
            if !hasAccounts {
                // No accounts, show a placeholder
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
            } else {
                // Show account management icon (SF Symbol only)
                Image(systemName: "person.2")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
            }

            // Account count badge (only show if more than 2 accounts)
            if totalAccountCount > 2 {
                VStack {
                    HStack {
                        Spacer()
                        Text("\(totalAccountCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
                .frame(width: 32, height: 32)
                .offset(x: 4, y: -4)
            }
        }
        .id(refreshTrigger)
        .onAppear {
            print(
                "UnifiedAccountsIcon appeared with \(mastodonAccounts.count) Mastodon accounts and \(blueskyAccounts.count) Bluesky accounts"
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileImageUpdated)) {
            notification in
            // Profile image updates will be handled through normal data flow
        }
    }
}

// MARK: - Alternative Design Variants

/// Compact horizontal layout variant with platform logos
struct UnifiedAccountsIconCompact: View {
    let mastodonAccounts: [SocialAccount]
    let blueskyAccounts: [SocialAccount]
    @Environment(\.colorScheme) var colorScheme

    private var hasAccounts: Bool {
        !mastodonAccounts.isEmpty || !blueskyAccounts.isEmpty
    }

    var body: some View {
        HStack(spacing: 4) {
            // Main accounts icon
            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.primary)

            if hasAccounts {
                // Platform logo stack
                VStack(spacing: 2) {
                    if !mastodonAccounts.isEmpty {
                        Image("MastodonLogo")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundStyle(Color.mastodonColor)
                            .frame(width: 8, height: 6)
                    }
                    if !blueskyAccounts.isEmpty {
                        Image("BlueskyLogo")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundStyle(Color.blueskyColor)
                            .frame(width: 8, height: 6)
                    }
                }
            }
        }
        .frame(width: 32, height: 32)
    }
}

/// Minimalist logo-only variant
struct UnifiedAccountsIconMinimal: View {
    let mastodonAccounts: [SocialAccount]
    let blueskyAccounts: [SocialAccount]
    @Environment(\.colorScheme) var colorScheme

    private var totalAccountCount: Int {
        mastodonAccounts.count + blueskyAccounts.count
    }

    public var body: some View {
        ZStack {
            // Clean background circle
            Circle()
                .fill(
                    colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6)
                )
                .frame(width: 32, height: 32)

            if totalAccountCount == 0 {
                Image(systemName: "plus.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
            } else {
                // Platform logos with counts
                HStack(spacing: 6) {
                    if !mastodonAccounts.isEmpty {
                        VStack(spacing: 2) {
                            Image("MastodonLogo")
                                .resizable()
                                .renderingMode(.template)
                                .foregroundStyle(Color.mastodonColor)
                                .frame(width: 12, height: 12)
                            if mastodonAccounts.count > 1 {
                                Text("\(mastodonAccounts.count)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(Color.mastodonColor)
                            }
                        }
                    }
                    if !blueskyAccounts.isEmpty {
                        VStack(spacing: 2) {
                            Image("BlueskyLogo")
                                .resizable()
                                .renderingMode(.template)
                                .foregroundStyle(Color.blueskyColor)
                                .frame(width: 12, height: 12)
                            if blueskyAccounts.count > 1 {
                                Text("\(blueskyAccounts.count)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(Color.blueskyColor)
                            }
                        }
                    }
                }
            }
        }
    }
}

// Helper extension removed (use global Color(hex:) instead)

// MARK: - Preview
struct UnifiedAccountsIcon_Previews: PreviewProvider {
    static let sampleMastodonAccount = SocialAccount(
        id: "mastodon-1",
        username: "user1",
        displayName: "User One",
        serverURL: "mastodon.social",
        platform: .mastodon,
        accessToken: "token"
    )

    static let sampleBlueskyAccount = SocialAccount(
        id: "bluesky-1",
        username: "user2",
        displayName: "User Two",
        serverURL: "bsky.social",
        platform: .bluesky,
        accessToken: "token"
    )

    static var previews: some View {
        VStack(spacing: 20) {
            Text("Unified Account Icon with Platform Logos")
                .font(.title2)
                .padding()

            HStack(spacing: 30) {
                VStack {
                    Text("No Accounts")
                        .font(.caption)
                    UnifiedAccountsIcon(
                        mastodonAccounts: [],
                        blueskyAccounts: []
                    )
                }

                VStack {
                    Text("Mastodon Only")
                        .font(.caption)
                    UnifiedAccountsIcon(
                        mastodonAccounts: [sampleMastodonAccount],
                        blueskyAccounts: []
                    )
                }

                VStack {
                    Text("Both Platforms")
                        .font(.caption)
                    UnifiedAccountsIcon(
                        mastodonAccounts: [sampleMastodonAccount],
                        blueskyAccounts: [sampleBlueskyAccount]
                    )
                }

                VStack {
                    Text("Multiple (5)")
                        .font(.caption)
                    UnifiedAccountsIcon(
                        mastodonAccounts: [
                            sampleMastodonAccount, sampleMastodonAccount, sampleMastodonAccount,
                        ],
                        blueskyAccounts: [sampleBlueskyAccount, sampleBlueskyAccount]
                    )
                }
            }

            Divider()

            Text("Alternative Designs")
                .font(.title3)
                .padding(.top)

            HStack(spacing: 30) {
                VStack {
                    Text("Compact")
                        .font(.caption)
                    UnifiedAccountsIconCompact(
                        mastodonAccounts: [sampleMastodonAccount],
                        blueskyAccounts: [sampleBlueskyAccount]
                    )
                }

                VStack {
                    Text("Minimal")
                        .font(.caption)
                    UnifiedAccountsIconMinimal(
                        mastodonAccounts: [sampleMastodonAccount, sampleMastodonAccount],
                        blueskyAccounts: [sampleBlueskyAccount]
                    )
                }
            }
        }
        .padding()
        .previewLayout(.sizeThatFits)
        .preferredColorScheme(.light)

        VStack(spacing: 20) {
            Text("Dark Mode Variants")
                .font(.title2)
                .padding()

            HStack(spacing: 30) {
                VStack {
                    Text("Main Design")
                        .font(.caption)
                    UnifiedAccountsIcon(
                        mastodonAccounts: [sampleMastodonAccount],
                        blueskyAccounts: [sampleBlueskyAccount]
                    )
                }

                VStack {
                    Text("Compact")
                        .font(.caption)
                    UnifiedAccountsIconCompact(
                        mastodonAccounts: [sampleMastodonAccount],
                        blueskyAccounts: [sampleBlueskyAccount]
                    )
                }

                VStack {
                    Text("Minimal")
                        .font(.caption)
                    UnifiedAccountsIconMinimal(
                        mastodonAccounts: [sampleMastodonAccount, sampleMastodonAccount],
                        blueskyAccounts: [sampleBlueskyAccount]
                    )
                }
            }
        }
        .padding()
        .previewLayout(.sizeThatFits)
        .preferredColorScheme(.dark)
    }
}
