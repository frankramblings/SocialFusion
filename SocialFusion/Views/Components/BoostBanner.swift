import SwiftUI

/// "<user> boosted" pill styled like ReplyBanner.
struct BoostBanner: View {
    let handle: String
    let platform: SocialPlatform
    let emojiMap: [String: String]?  // Emoji for the booster's display name

    // Animation state for subtle interactions
    @State private var isPressed = false
    
    init(handle: String, platform: SocialPlatform, emojiMap: [String: String]? = nil) {
        self.handle = handle
        self.platform = platform
        self.emojiMap = emojiMap
    }

    private var platformColor: Color {
        switch platform {
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "repeat")
                .font(.caption)
                .foregroundColor(platformColor)
                .scaleEffect(isPressed ? 0.95 : 1.0)
            HStack(spacing: 0) {
                EmojiDisplayNameText(
                    handle,
                    emojiMap: emojiMap,
                    font: .caption,
                    fontWeight: .regular,
                    foregroundColor: .secondary,
                    lineLimit: 1
                )
                Text(" boosted")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .opacity(isPressed ? 0.8 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .contentShape(Rectangle())
        .onLongPressGesture(
            minimumDuration: 0, maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            }, perform: {})
    }
}

protocol BoostBannerViewModel {
    func loadBoostersIfNeeded(for postID: String) async
    func openProfile(userID: String)
    func mute(userID: String)
    func block(userID: String)
    func follow(userID: String)
    func unfollow(userID: String)
}

struct BoostBannerView<ViewModel: BoostBannerViewModel>: View {
    @ObservedObject var post: Post
    let viewModel: ViewModel

    @State private var isExpanded = false
    @State private var showContent = false
    @State private var isPressed = false
    @State private var hasTriggeredLoad = false

    private var expandAnimation: Animation {
        .timingCurve(0.4, 0.0, 0.6, 1.0, duration: 0.45)
    }

    private var collapseAnimation: Animation {
        .timingCurve(0.4, 0.0, 0.6, 1.0, duration: 0.35)
    }

    private var chevronAnimation: Animation {
        .timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.3)
    }

    private var visibleBoosters: [User] {
        let source = (post.boosters?.isEmpty == false) ? (post.boosters ?? []) : post.boostersPreview
        // Show only people the user follows; blocked users are always excluded.
        return source.filter { $0.isFollowedByMe && !$0.isBlocked }
    }

    private var sortedBoosters: [User] {
        let indexed = visibleBoosters.enumerated().map { (offset: $0.offset, user: $0.element) }
        return indexed.sorted { lhs, rhs in
            let lhsRank = relationshipRank(for: lhs.user)
            let rhsRank = relationshipRank(for: rhs.user)
            if lhsRank != rhsRank { return lhsRank < rhsRank }

            if let lhsDate = lhs.user.boostedAt, let rhsDate = rhs.user.boostedAt {
                if lhsDate != rhsDate { return lhsDate > rhsDate }
            } else if lhs.user.boostedAt != nil || rhs.user.boostedAt != nil {
                return lhs.user.boostedAt != nil
            }

            return lhs.offset < rhs.offset
        }.map { $0.user }
    }

    private func relationshipRank(for user: User) -> Int {
        if user.isFollowedByMe { return 0 }
        if user.followsMe { return 1 }
        return 2
    }

    private var collapsedBoosters: [User] {
        Array(sortedBoosters.prefix(2))
    }

    private var collapsedText: String {
        guard collapsedBoosters.count >= 2 else { return "Boosted by multiple users" }
        let first = displayName(for: collapsedBoosters[0])
        let second = displayName(for: collapsedBoosters[1])
        if post.boostCount == 2 {
            return "Boosted by \(first) & \(second)"
        }
        let remaining = max(0, post.boostCount - 2)
        return "Boosted by \(first), \(second) + \(remaining) more"
    }

    private var collapsedAccessibilityLabel: String {
        "\(collapsedText). Double-tap to view all boosters."
    }

    private var platformColor: Color {
        switch post.platform {
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)
        }
    }

    // MARK: - Extracted Subviews (helps type-checker)

    private var bannerHeaderContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "repeat")
                .font(.caption)
                .foregroundColor(platformColor)

            OverlappingAvatarStack(users: collapsedBoosters, size: 18, overlapFraction: 0.33)

            Text(collapsedText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(chevronAnimation, value: isExpanded)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var collapsedBackground: some View {
        if !isExpanded {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if isExpanded {
            if post.boosters == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(sortedBoosters) { booster in
                        BoosterRowView(user: booster, viewModel: viewModel)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    private var cornerRadius: CGFloat {
        isExpanded ? 20 : 12
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: handleBannerTap) {
                bannerHeaderContent
                    .background(collapsedBackground)
                    .contentShape(Rectangle())
                    .scaleEffect(isPressed ? 0.98 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isPressed)
            }
            .buttonStyle(PlainButtonStyle())
            .onLongPressGesture(
                minimumDuration: 0, maximumDistance: .infinity,
                pressing: { pressing in
                    isPressed = pressing
                    if pressing {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }
                }, perform: {}
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(collapsedAccessibilityLabel)

            expandedContent
                .opacity(showContent ? 1 : 0)
                .scaleEffect(showContent ? 1 : 0.98, anchor: .top)
                .frame(height: isExpanded ? nil : 0)
                .clipped()
                .animation(isExpanded ? expandAnimation : collapseAnimation, value: showContent)
                .background(Color(.systemBackground).opacity(0.01))
        }
        .background(containerBackground)
        .overlay(containerOverlay)
        .shadow(
            color: isExpanded ? Color.black.opacity(0.06) : Color.black.opacity(0.02),
            radius: isExpanded ? 4 : 1,
            x: 0,
            y: isExpanded ? 2 : 0.5
        )
        .background(liquidGlassBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onChange(of: isExpanded) { newValue in
            withAnimation(newValue ? expandAnimation : collapseAnimation) {
                showContent = newValue
            }

            if newValue && post.boosters == nil && !hasTriggeredLoad {
                hasTriggeredLoad = true
                Task {
                    await viewModel.loadBoostersIfNeeded(for: post.id)
                }
            }
        }
    }

    private var containerBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                isExpanded
                    ? AnyShapeStyle(Color.clear)
                    : AnyShapeStyle(Color(.systemBackground))
            )
            .animation(isExpanded ? expandAnimation : collapseAnimation, value: isExpanded)
    }

    private var containerOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                Color.secondary.opacity(isExpanded ? 0.12 : 0.2),
                lineWidth: isExpanded ? 0.5 : 1
            )
            .animation(isExpanded ? expandAnimation : collapseAnimation, value: isExpanded)
    }

    @ViewBuilder
    private var liquidGlassBackground: some View {
        if isExpanded {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.clear)
                .advancedLiquidGlass(
                    variant: .morphing,
                    intensity: 0.9,
                    morphingState: isPressed ? .pressed : .expanded
                )
        }
    }

    private func handleBannerTap() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.prepare()
        impactFeedback.impactOccurred()

        withAnimation(isExpanded ? collapseAnimation : expandAnimation) {
            isExpanded.toggle()
        }
    }

    private func displayName(for user: User) -> String {
        user.displayName?.isEmpty == false ? (user.displayName ?? "") : user.username
    }
}

struct BoosterRowView<ViewModel: BoostBannerViewModel>: View {
    let user: User
    let viewModel: ViewModel

    var body: some View {
        Button(action: { viewModel.openProfile(userID: user.id) }) {
            HStack(spacing: 12) {
                BoosterAvatarView(url: user.avatarURL, size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName?.isEmpty == false ? (user.displayName ?? "") : user.username)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text("@\(user.username)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button("View Profile") {
                viewModel.openProfile(userID: user.id)
            }
            Button(user.isFollowedByMe ? "Unfollow" : "Follow") {
                if user.isFollowedByMe {
                    viewModel.unfollow(userID: user.id)
                } else {
                    viewModel.follow(userID: user.id)
                }
            }
            Button("Mute") { viewModel.mute(userID: user.id) }
            Button("Block", role: .destructive) { viewModel.block(userID: user.id) }
        }
    }
}

struct OverlappingAvatarStack: View {
    let users: [User]
    let size: CGFloat
    let overlapFraction: CGFloat

    var body: some View {
        HStack(spacing: -size * overlapFraction) {
            ForEach(users) { user in
                BoosterAvatarView(url: user.avatarURL, size: size)
                    .overlay(
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 1)
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct BoosterAvatarView: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url = url {
                CachedAsyncImage(url: url, priority: .high) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle().fill(Color.secondary.opacity(0.2))
                }
            } else {
                Circle().fill(Color.secondary.opacity(0.2))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct BoostBannerViewModelAdapter: BoostBannerViewModel {
    let platform: SocialPlatform
    let serviceManager: SocialServiceManager
    let navigationEnvironment: PostNavigationEnvironment
    let userResolver: (String) -> User?
    let postProvider: () -> Post?

    func loadBoostersIfNeeded(for postID: String) async {
        guard let post = postProvider(), post.id == postID else { return }
        guard post.boosters == nil else { return }

        do {
            let boosters = try await serviceManager.fetchBoosters(for: post)
            await MainActor.run {
                post.boosters = boosters
                post.boostersPreview = Array(boosters.prefix(2))
            }
        } catch {
            ErrorHandler.shared.handleError(error)
        }
    }

    func openProfile(userID: String) {
        Task { @MainActor in
            if let user = userResolver(userID) {
                let searchUser = SearchUser(
                    id: user.id,
                    username: user.username,
                    displayName: user.displayName,
                    avatarURL: user.avatarURL?.absoluteString,
                    platform: platform
                )
                navigationEnvironment.selectedUser = searchUser
            } else {
                let searchUser = SearchUser(
                    id: userID,
                    username: userID,
                    displayName: nil,
                    avatarURL: nil,
                    platform: platform
                )
                navigationEnvironment.selectedUser = searchUser
            }
        }
    }

    func mute(userID: String) {
        Task {
            do {
                try await serviceManager.muteUser(userId: userID, platform: platform)
            } catch {
                ErrorHandler.shared.handleError(error)
            }
        }
    }

    func block(userID: String) {
        Task {
            do {
                try await serviceManager.blockUser(userId: userID, platform: platform)
            } catch {
                ErrorHandler.shared.handleError(error)
            }
        }
    }

    func follow(userID: String) {
        Task {
            do {
                try await serviceManager.followUser(userId: userID, platform: platform)
            } catch {
                ErrorHandler.shared.handleError(error)
            }
        }
    }

    func unfollow(userID: String) {
        Task {
            do {
                try await serviceManager.unfollowUser(userId: userID, platform: platform)
            } catch {
                ErrorHandler.shared.handleError(error)
            }
        }
    }
}
