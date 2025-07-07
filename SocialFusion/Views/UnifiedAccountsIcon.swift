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

    var body: some View {
        ZStack {
            if !hasAccounts {
                // No accounts, show a placeholder
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
            } else {
                // Show account management icon with platform logos
                VStack(spacing: 2) {
                    // Main account icon
                    Image(
                        systemName: totalAccountCount == 1
                            ? "person.circle.fill" : "person.2.circle.fill"
                    )
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)

                    // Platform logo indicators
                    HStack(spacing: 2) {
                        if !mastodonAccounts.isEmpty {
                            Image("MastodonLogo")
                                .resizable()
                                .renderingMode(.template)
                                .foregroundStyle(Color(hex: "6364FF"))
                                .frame(width: 8, height: 8)
                        }
                        if !blueskyAccounts.isEmpty {
                            Image("BlueskyLogo")
                                .resizable()
                                .renderingMode(.template)
                                .foregroundStyle(Color(hex: "0085FF"))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
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
                            .foregroundStyle(Color(hex: "6364FF"))
                            .frame(width: 8, height: 6)
                    }
                    if !blueskyAccounts.isEmpty {
                        Image("BlueskyLogo")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundStyle(Color(hex: "0085FF"))
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

    var body: some View {
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
                                .foregroundStyle(Color(hex: "6364FF"))
                                .frame(width: 12, height: 12)
                            if mastodonAccounts.count > 1 {
                                Text("\(mastodonAccounts.count)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(Color(hex: "6364FF"))
                            }
                        }
                    }
                    if !blueskyAccounts.isEmpty {
                        VStack(spacing: 2) {
                            Image("BlueskyLogo")
                                .resizable()
                                .renderingMode(.template)
                                .foregroundStyle(Color(hex: "0085FF"))
                                .frame(width: 12, height: 12)
                            if blueskyAccounts.count > 1 {
                                Text("\(blueskyAccounts.count)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(Color(hex: "0085FF"))
                            }
                        }
                    }
                }
            }
        }
    }
}

// Helper extension for hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:  // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview
struct UnifiedAccountsIcon_Previews: PreviewProvider {
    static let sampleMastodonAccount = SocialAccount(
        id: "mastodon-1",
        platform: .mastodon,
        username: "user1",
        displayName: "User One",
        profileImageURL: nil,
        serverURL: "mastodon.social",
        accessToken: "token"
    )

    static let sampleBlueskyAccount = SocialAccount(
        id: "bluesky-1",
        platform: .bluesky,
        username: "user2",
        displayName: "User Two",
        profileImageURL: nil,
        serverURL: "bsky.social",
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
