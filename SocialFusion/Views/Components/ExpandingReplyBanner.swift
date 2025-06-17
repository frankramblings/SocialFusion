import SwiftUI

// HeightPreferenceKey for smooth height measurement updates
private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// Simple PostParentCache for ExpandingReplyBanner
class PostParentCache: ObservableObject {
    static let shared = PostParentCache()
    @Published var cache = [String: Post]()
    private var fetching = Set<String>()

    private init() {}

    func isFetching(id: String) -> Bool {
        return fetching.contains(id)
    }

    func getCachedPost(id: String) -> Post? {
        return cache[id]
    }

    func preloadParentPost(
        id: String, username: String, platform: SocialPlatform,
        serviceManager: SocialServiceManager, allAccounts: [SocialAccount]
    ) {
        fetchRealPost(
            id: id, username: username, platform: platform,
            serviceManager: serviceManager, allAccounts: allAccounts
        )
    }

    func fetchRealPost(
        id: String, username: String, platform: SocialPlatform,
        serviceManager: SocialServiceManager, allAccounts: [SocialAccount]
    ) {
        guard !fetching.contains(id) else { return }
        fetching.insert(id)

        Task {
            do {
                let post: Post?

                switch platform {
                case .mastodon:
                    if let account = allAccounts.first(where: { $0.platform == .mastodon }) {
                        post = try await serviceManager.fetchMastodonStatus(
                            id: id, account: account)
                    } else {
                        post = nil
                    }
                case .bluesky:
                    post = try await serviceManager.fetchBlueskyPostByID(id)
                }

                _ = await MainActor.run {
                    self.fetching.remove(id)
                    if let post = post {
                        self.cache[id] = post
                    }
                }
            } catch {
                _ = await MainActor.run {
                    self.fetching.remove(id)
                }
            }
        }
    }
}

struct ExpandingReplyBanner: View {
    let username: String
    let network: SocialPlatform
    let parentId: String?
    @Binding var isExpanded: Bool
    var onBannerTap: (() -> Void)? = nil
    var onParentPostTap: ((Post) -> Void)? = nil
    @ObservedObject private var parentCache = PostParentCache.shared
    @State private var parent: Post? = nil
    @State private var fetchAttempted = false

    // Smooth animation state
    @State private var isPressed = false
    @State private var contentHeight: CGFloat = 0
    @State private var showContent = false

    private var displayUsername: String {
        if let parent = parent {
            if !parent.authorUsername.isEmpty && parent.authorUsername != "unknown.bsky.social"
                && parent.authorUsername != "unknown" && !parent.isPlaceholder
            {
                return parent.authorUsername
            }
        }
        return username
    }

    private var shouldShowLoadingState: Bool {
        guard let parentId = parentId else { return false }
        return isExpanded
            && (parentCache.isFetching(id: parentId) || (parent?.isPlaceholder == true))
    }

    private var platformColor: Color {
        switch network {
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
        }
    }

    // Ultra-smooth liquid glass animation
    private var fluidAnimation: Animation {
        .easeInOut(duration: 0.5)
    }

    private var chevronAnimation: Animation {
        .easeInOut(duration: 0.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Banner row with refined interaction feedback
            Button(action: handleBannerTap) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.up.left")
                        .font(.caption)
                        .foregroundColor(platformColor)
                        .scaleEffect(isPressed ? 0.95 : 1.0)

                    Text("Replying to @\(displayUsername)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if shouldShowLoadingState {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .scaleEffect(isPressed ? 0.9 : 1.0)
                        .animation(chevronAnimation, value: isExpanded)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .scaleEffect(isPressed ? 0.98 : 1.0)
            }
            .buttonStyle(PlainButtonStyle())
            .onLongPressGesture(
                minimumDuration: 0, maximumDistance: .infinity,
                pressing: { pressing in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = pressing
                    }
                }, perform: {}
            )
            .zIndex(1)  // Ensure banner is above content for tap handling

            // Content with smooth height animation
            contentView
                .background(Color(.systemGray6))  // Opaque background to prevent transparency
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .preference(key: HeightPreferenceKey.self, value: geometry.size.height)
                    }
                )
                .frame(height: showContent ? contentHeight : 0)
                .clipped()
                .animation(fluidAnimation, value: showContent)
                .onPreferenceChange(HeightPreferenceKey.self) { newHeight in
                    if contentHeight != newHeight {
                        contentHeight = newHeight
                    }
                }
                .allowsHitTesting(showContent && isExpanded)  // Only allow content interaction when fully expanded
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isExpanded ? Color(.systemGray6) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    Color.secondary.opacity(isExpanded ? 0.15 : 0.2),
                    lineWidth: isExpanded ? 0.5 : 1
                )
        )
        .shadow(
            color: isExpanded ? Color.black.opacity(0.04) : Color.clear,
            radius: isExpanded ? 2 : 0,
            x: 0,
            y: isExpanded ? 1 : 0
        )
        .animation(fluidAnimation, value: isExpanded)
        .onReceive(parentCache.$cache) { cache in
            guard let parentId = parentId else { return }
            let newParent = cache[parentId]
            if parent !== newParent {
                parent = newParent
                // Reset content height when parent changes to trigger recalculation
                contentHeight = 0
            }
        }
        .onAppear {
            // Set initial parent from cache immediately
            if let parentId = parentId {
                parent = parentCache.getCachedPost(id: parentId)

                // Preload in background for smoother experience
                if !parentCache.isFetching(id: parentId) && parent == nil {
                    triggerBackgroundPreload(parentId: parentId)
                }
            }

            // Initialize showContent state
            showContent = isExpanded
        }
        .onChange(of: isExpanded) { newValue in
            withAnimation(fluidAnimation) {
                showContent = newValue
            }
        }
    }

    // Content view - rendered when needed
    @ViewBuilder
    private var contentView: some View {
        if let parent = parent, !parent.isPlaceholder {
            // Real parent post content
            ParentPostPreview(post: parent) {
                onParentPostTap?(parent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        } else if shouldShowLoadingState {
            // Skeleton loading state
            ParentPostSkeleton()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        } else if fetchAttempted && parent == nil {
            // Error state
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                    .font(.title2)
                Text("Unable to load parent post")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
        } else {
            // Placeholder content
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 80, height: 12)
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 14)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 200, height: 14)
                }
                .padding(.leading, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func handleBannerTap() {
        // Provide refined haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.prepare()
        impactFeedback.impactOccurred()

        // Toggle expansion state
        isExpanded.toggle()

        // Start fetching when expanded
        if isExpanded, let parentId = parentId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                triggerParentFetch(parentId: parentId)
            }
        }

        onBannerTap?()
    }

    private func triggerBackgroundPreload(parentId: String) {
        parentCache.preloadParentPost(
            id: parentId,
            username: username,
            platform: network,
            serviceManager: SocialServiceManager.shared,
            allAccounts: SocialServiceManager.shared.mastodonAccounts
                + SocialServiceManager.shared.blueskyAccounts
        )
    }

    private func triggerParentFetch(parentId: String) {
        guard parent == nil || parent?.isPlaceholder == true else { return }

        if !parentCache.isFetching(id: parentId) {
            fetchAttempted = true
            parentCache.fetchRealPost(
                id: parentId,
                username: username,
                platform: network,
                serviceManager: SocialServiceManager.shared,
                allAccounts: SocialServiceManager.shared.mastodonAccounts
                    + SocialServiceManager.shared.blueskyAccounts
            )
        }
    }
}

// Refined skeleton loading state without opacity animations
struct ParentPostSkeleton: View {
    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Avatar skeleton with shimmer effect
                Circle()
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.clear,
                                        Color.white.opacity(0.3),
                                        Color.clear,
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .offset(x: shimmerOffset)
                            .clipped()
                    )

                VStack(alignment: .leading, spacing: 4) {
                    // Username skeleton
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 85, height: 14)

                    // Handle skeleton
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 65, height: 11)
                }

                Spacer()

                // Time skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 35, height: 11)
            }

            // Content skeleton with varied widths
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.25))
                    .frame(height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 220, height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 160, height: 14)
            }
            .padding(.leading, 4)
        }
        .onAppear {
            // Start gentle shimmer animation
            withAnimation(
                .easeInOut(duration: 2.0)
                    .repeatForever(autoreverses: false)
            ) {
                shimmerOffset = 200
            }
        }
    }
}

struct ExpandingReplyBanner_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Bluesky reply banner
            ExpandingReplyBanner(
                username: "testuser",
                network: .bluesky,
                parentId: nil,
                isExpanded: .constant(false)
            )

            // Mastodon reply banner
            ExpandingReplyBanner(
                username: "testuser",
                network: .mastodon,
                parentId: nil,
                isExpanded: .constant(true)
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
