import Foundation
import SwiftUI

/// A redesigned top bar for the post composer featuring circular profile pictures with platform badges
/// Uses Liquid Glass aesthetics and supports multiple accounts per platform
struct PostComposerTopBar: View {
    @ObservedObject var socialServiceManager: SocialServiceManager
    @Binding var selectedAccountIds: Set<String>
    @Binding var selectedVisibility: Int
    @State private var showAccountPicker = false
    @State private var selectedPlatformForPicker: SocialPlatform? = nil
    @Environment(\.colorScheme) private var colorScheme

    let postVisibilityOptions = ["Public", "Unlisted", "Followers Only"]

    // For sheet presentation with specific account selection
    @State private var accountPickerAccountId: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // Profile pictures section with horizontal scroll for many accounts
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(socialServiceManager.accounts, id: \.id) { account in
                            ProfileToggleButton(
                                account: account,
                                isSelected: selectedAccountIds.contains(account.id)
                                    || selectedAccountIds.contains("all"),
                                onTap: {
                                    toggleAccount(account)
                                },
                                onLongPress: {
                                    // Long press to switch accounts for this platform
                                    selectedPlatformForPicker = account.platform
                                    accountPickerAccountId = account.id
                                    showAccountPicker = true
                                }
                            )
                        }

                        // Show hint if no accounts
                        if socialServiceManager.accounts.isEmpty {
                            UnifiedAccountsIcon(
                                mastodonAccounts: socialServiceManager.mastodonAccounts,
                                blueskyAccounts: socialServiceManager.blueskyAccounts
                            )
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer()

                // Visibility picker with Liquid Glass styling
                VisibilityButton(
                    selectedVisibility: $selectedVisibility, options: postVisibilityOptions)
            }
            .padding(.vertical, 12)
            .background(Material.regularMaterial)
            .overlay(
                Divider(),
                alignment: .bottom
            )
        }
        .sheet(isPresented: $showAccountPicker) {
            if let platform = selectedPlatformForPicker {
                AccountSwitcherSheet(
                    platform: platform,
                    currentAccountId: accountPickerAccountId,
                    socialServiceManager: socialServiceManager,
                    onAccountSelected: { newAccountId in
                        // Replace the old account selection with the new one
                        if let oldAccountId = accountPickerAccountId {
                            selectedAccountIds.remove(oldAccountId)
                        }
                        selectedAccountIds.insert(newAccountId)
                        showAccountPicker = false
                    }
                )
            }
        }
    }

    private func toggleAccount(_ account: SocialAccount) {
        if selectedAccountIds.contains("all") {
            // If "all" is selected, switch to individual selection
            selectedAccountIds = [account.id]
        } else if selectedAccountIds.contains(account.id) {
            selectedAccountIds.remove(account.id)
            // If no accounts are selected, default to "all"
            if selectedAccountIds.isEmpty {
                selectedAccountIds = ["all"]
            }
        } else {
            selectedAccountIds.insert(account.id)
        }
    }
}

/// Profile picture button with platform badge that can be toggled on/off
struct ProfileToggleButton: View {
    let account: SocialAccount
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    private let avatarSize: CGFloat = 44

    var body: some View {
        Button(action: onTap) {
            // Create a container that provides enough space for the badge and selection ring
            ZStack {
                // Background glow effect for active accounts
                if isSelected {
                    Circle()
                        .fill(account.platform.color.opacity(0.1))
                        .frame(width: avatarSize + 8, height: avatarSize + 8)
                        .blur(radius: 8)
                }

                // Selection ring positioned behind the profile image
                if isSelected {
                    Circle()
                        .stroke(account.platform.color, lineWidth: 3)
                        .frame(width: avatarSize + 6, height: avatarSize + 6)
                        .shadow(
                            color: account.platform.color.opacity(0.3),
                            radius: 4,
                            x: 0,
                            y: 2
                        )
                }

                // Profile image with existing platform badge (PostAuthorImageView already includes PlatformLogoBadge)
                PostAuthorImageView(
                    authorProfilePictureURL: account.profileImageURL?.absoluteString ?? "",
                    platform: account.platform,
                    size: avatarSize,
                    authorName: account.displayName ?? account.username
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .opacity(isSelected ? 1.0 : 0.5)
                .saturation(isSelected ? 1.0 : 0.3)
            }
            .frame(width: avatarSize + 12, height: avatarSize + 12)  // Extra space to prevent clipping of badge and selection ring
        }
        .buttonStyle(.plain)
        .onLongPressGesture {
            onLongPress()
        }
        .onAppear {
            // REMOVED: Animation delay that was causing AttributeGraph cycles
            // Proper SwiftUI state management doesn't need artificial delays
        }
        // Note: sensoryFeedback is iOS 17+, removed for iOS 16 compatibility
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
    }
}

/// Visibility control button with Liquid Glass styling
struct VisibilityButton: View {
    @Binding var selectedVisibility: Int
    let options: [String]
    @Environment(\.colorScheme) private var colorScheme

    private var visibilityIcon: String {
        switch selectedVisibility {
        case 0: return "eye"  // Public
        case 1: return "eye.slash"  // Unlisted
        case 2: return "lock"  // Followers Only
        default: return "eye"
        }
    }

    var body: some View {
        Menu {
            Picker("Visibility", selection: $selectedVisibility) {
                ForEach(0..<options.count, id: \.self) { index in
                    HStack {
                        Image(systemName: iconForIndex(index))
                        Text(options[index])
                    }
                    .tag(index)
                }
            }
        } label: {
            Image(systemName: visibilityIcon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(Material.regularMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: selectedVisibility)
    }

    private func iconForIndex(_ index: Int) -> String {
        switch index {
        case 0: return "eye"
        case 1: return "eye.slash"
        case 2: return "lock"
        default: return "eye"
        }
    }
}

/// Empty state when no accounts are available
struct EmptyAccountsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Add Account")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 44, height: 44)
        .background(Material.ultraThinMaterial, in: Circle())
        .overlay(
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

/// Account switcher sheet for long-press action
struct AccountSwitcherSheet: View {
    let platform: SocialPlatform
    let currentAccountId: String?
    @ObservedObject var socialServiceManager: SocialServiceManager
    let onAccountSelected: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private var platformAccounts: [SocialAccount] {
        socialServiceManager.accounts.filter { $0.platform == platform }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(platformAccounts, id: \.id) { account in
                        HStack(spacing: 12) {
                            PostAuthorImageView(
                                authorProfilePictureURL: account.profileImageURL?.absoluteString
                                    ?? "",
                                platform: account.platform,
                                size: 32,
                                authorName: account.displayName ?? account.username
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName ?? account.username)
                                    .font(.headline)

                                Text("@\(account.username)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if account.id == currentAccountId {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(platform.color)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onAccountSelected(account.id)
                        }
                    }
                } header: {
                    HStack {
                        Image(platform == .mastodon ? "MastodonLogo" : "BlueskyLogo")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundStyle(platform.color)
                            .frame(width: 16, height: 16)

                        Text("\(platform.rawValue.capitalized) Accounts")
                    }
                }
            }
            .navigationTitle("Switch Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    VStack {
        PostComposerTopBar(
            socialServiceManager: SocialServiceManager.shared,
            selectedAccountIds: .constant(["all"]),
            selectedVisibility: .constant(0)
        )

        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}
