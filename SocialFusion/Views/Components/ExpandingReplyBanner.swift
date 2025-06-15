import SwiftUI

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

                await MainActor.run {
                    self.fetching.remove(id)
                    if let post = post {
                        self.cache[id] = post
                    }
                }
            } catch {
                await MainActor.run {
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
    @ObservedObject private var parentCache = PostParentCache.shared
    @State private var parent: Post? = nil
    @State private var fetchAttempted = false

    // Enhanced animation state management
    @State private var isAnimating = false
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

    // Apple-style animation curves
    private var expandAnimation: Animation {
        .timingCurve(0.2, 0.0, 0.0, 1.0, duration: 0.45)
    }

    private var collapseAnimation: Animation {
        .timingCurve(0.4, 0.0, 0.6, 1.0, duration: 0.35)
    }

    private var chevronAnimation: Animation {
        .timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Banner row with enhanced interaction feedback
            Button(action: {
                handleBannerTap()
            }) {
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
                            .transition(.scale.combined(with: .opacity))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .scaleEffect(isPressed ? 0.9 : 1.0)
                        .animation(chevronAnimation, value: isExpanded)
                        .animation(.easeInOut(duration: 0.1), value: isPressed)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .scaleEffect(isPressed ? 0.98 : 1.0)
                .opacity(isPressed ? 0.8 : 1.0)
            }
            .buttonStyle(PlainButtonStyle())
            .onLongPressGesture(
                minimumDuration: 0, maximumDistance: .infinity,
                pressing: { pressing in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = pressing
                    }
                }, perform: {})

            // Parent post preview with refined animations
            if isExpanded {
                Group {
                    if let parent = parent, !parent.isPlaceholder {
                        // Real parent post content
                        ParentPostPreview(post: parent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .opacity(showContent ? 1 : 0)
                            .scaleEffect(showContent ? 1 : 0.96)
                            .offset(y: showContent ? 0 : -8)
                            .transition(
                                .asymmetric(
                                    insertion: .identity,
                                    removal: .opacity.combined(with: .scale(scale: 0.96)).combined(
                                        with: .offset(y: -8))
                                )
                            )
                    } else if shouldShowLoadingState {
                        // Skeleton loading state with refined animation
                        ParentPostSkeleton()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .opacity(showContent ? 1 : 0)
                            .scaleEffect(showContent ? 1 : 0.96)
                            .offset(y: showContent ? 0 : -8)
                            .transition(
                                .asymmetric(
                                    insertion: .identity,
                                    removal: .opacity.combined(with: .scale(scale: 0.96)).combined(
                                        with: .offset(y: -8))
                                )
                            )
                    } else if fetchAttempted && parent == nil {
                        // Error state with refined animation
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
                        .opacity(showContent ? 1 : 0)
                        .scaleEffect(showContent ? 1 : 0.96)
                        .offset(y: showContent ? 0 : -8)
                        .transition(
                            .asymmetric(
                                insertion: .identity,
                                removal: .opacity.combined(with: .scale(scale: 0.96)).combined(
                                    with: .offset(y: -8))
                            )
                        )
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isExpanded ? Color(.systemGray6) : Color(.systemBackground))
                .animation(isExpanded ? expandAnimation : collapseAnimation, value: isExpanded)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    Color.secondary.opacity(isExpanded ? 0.15 : 0.2),
                    lineWidth: isExpanded ? 0.5 : 1
                )
                .animation(isExpanded ? expandAnimation : collapseAnimation, value: isExpanded)
        )
        .shadow(
            color: isExpanded ? Color.black.opacity(0.04) : Color.clear,
            radius: isExpanded ? 2 : 0,
            x: 0,
            y: isExpanded ? 1 : 0
        )
        .animation(isExpanded ? expandAnimation : collapseAnimation, value: isExpanded)
        .onReceive(parentCache.$cache) { cache in
            // Only update parent state when not animating to preserve animation context
            guard !isAnimating, let parentId = parentId else { return }
            let newParent = cache[parentId]
            if parent !== newParent {
                parent = newParent
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
        }
        .onChange(of: isExpanded) { newValue in
            if newValue {
                // Expanding: show content with delay for smooth animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(expandAnimation.delay(0.1)) {
                        showContent = true
                    }
                }
            } else {
                // Collapsing: hide content immediately for snappy feel
                withAnimation(collapseAnimation) {
                    showContent = false
                }
            }
        }
    }

    private func handleBannerTap() {
        // Prevent multiple rapid taps during animation
        guard !isAnimating else { return }

        // Provide refined haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.prepare()
        impactFeedback.impactOccurred()

        isAnimating = true

        // Use different animations for expand vs collapse
        let animation = isExpanded ? collapseAnimation : expandAnimation

        withAnimation(animation) {
            isExpanded.toggle()
        }

        // Reset animation state with proper timing
        let duration = isExpanded ? 0.35 : 0.45
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
            isAnimating = false
        }

        // Start fetching when expanded - delay to avoid interfering with animation
        if isExpanded, let parentId = parentId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                triggerParentFetch(parentId: parentId)
            }
        }

        onBannerTap?()
    }

    private func triggerBackgroundPreload(parentId: String) {
        // Use the enhanced preload method from PostParentCache
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

// Enhanced skeleton loading state with refined animations
struct ParentPostSkeleton: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Avatar skeleton with subtle pulse
                Circle()
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .fill(Color.gray.opacity(0.1))
                            .scaleEffect(isAnimating ? 1.1 : 1.0)
                            .opacity(isAnimating ? 0 : 1)
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

            // Content skeleton with varied widths for realism
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
        .opacity(isAnimating ? 0.7 : 1.0)
        .animation(
            .easeInOut(duration: 1.8)
                .repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear {
            // Stagger animation start for more natural feel
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isAnimating = true
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
