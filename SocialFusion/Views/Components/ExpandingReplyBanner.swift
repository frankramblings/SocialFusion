import Combine
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

        _ = Task {
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
    var onParentPostTap: ((Post) -> Void)? = nil
    @ObservedObject private var parentCache = PostParentCache.shared
    @State private var parent: Post? = nil
    @State private var fetchAttempted = false

    // Enhanced animation state management
    @State private var isPressed = false
    @State private var showContent = false
    @State private var contentHeight: CGFloat = 0
    @Environment(\.isLiquidGlassEnabled) private var isLiquidGlassEnabled

    // Apple-style animation timing curves
    private var expandAnimation: Animation {
        .timingCurve(0.4, 0.0, 0.6, 1.0, duration: 0.45)
    }

    private var collapseAnimation: Animation {
        .timingCurve(0.4, 0.0, 0.6, 1.0, duration: 0.35)
    }

    private var chevronAnimation: Animation {
        .timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.3)
    }

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

    // Liquid glass morphing state based on banner state
    private var liquidGlassMorphingState: MorphingState {
        if isPressed {
            return .pressed
        } else if isExpanded {
            return .expanded
        } else {
            return .idle
        }
    }

    // Liquid glass variant based on expansion state
    private var liquidGlassVariant: LiquidGlassVariant {
        return isExpanded ? .morphing : .regular
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Banner row with liquid glass effects
            Button(action: handleBannerTap) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.up.left")
                        .font(.caption)
                        .foregroundColor(platformColor)
                        .scaleEffect(isPressed ? 0.95 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: isPressed)

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
                        .animation(.easeInOut(duration: 0.1), value: isPressed)
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
                    withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = pressing
                    }
                    // Add haptic feedback for better interaction
                    if pressing {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }
                }, perform: {}
            )

            // Parent post preview - always present, height controlled
            Group {
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
                }
            }
            .opacity(showContent ? 1 : 0)
            .scaleEffect(showContent ? 1 : 0.98, anchor: .top)
            .frame(height: isExpanded ? nil : 0)
            .clipped()
            .background(
                // Simplified content background matching main container
                Color(.systemBackground).opacity(0.01)
            )
        }
        .background(
            // Background that matches boost banner in closed state, morphs to expanded state
            RoundedRectangle(cornerRadius: isExpanded ? 20 : 12, style: .continuous)
                .fill(
                    isExpanded
                        ? AnyShapeStyle(.ultraThinMaterial)
                        : AnyShapeStyle(Color(.systemBackground))
                )
                .animation(isExpanded ? expandAnimation : collapseAnimation, value: isExpanded)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isExpanded ? 20 : 12, style: .continuous)
                .stroke(
                    Color.secondary.opacity(isExpanded ? 0.12 : 0.2),
                    lineWidth: isExpanded ? 0.5 : 1
                )
                .animation(isExpanded ? expandAnimation : collapseAnimation, value: isExpanded)
        )
        .shadow(
            color: isExpanded ? Color.black.opacity(0.06) : Color.black.opacity(0.02),
            radius: isExpanded ? 4 : 1,
            x: 0,
            y: isExpanded ? 2 : 0.5
        )
        .animation(isExpanded ? expandAnimation : collapseAnimation, value: isExpanded)
        // Apply liquid glass effects to the entire banner
        .advancedLiquidGlass(
            variant: liquidGlassVariant,
            intensity: isExpanded ? 0.9 : 0.7,
            morphingState: liquidGlassMorphingState
        )
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 20 : 12, style: .continuous))
        .animation(isExpanded ? expandAnimation : collapseAnimation, value: isExpanded)
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
        .onReceive(parentCache.$cache) { cache in
            // Simple parent update - no complex state synchronization
            if let parentId = parentId {
                parent = cache[parentId]
            }
        }
        .onChange(of: isExpanded) { newValue in
            // Ensure showContent state stays synchronized with expansion
            if !newValue {
                showContent = false
            }
        }
    }

    private func handleBannerTap() {
        // Provide refined haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.prepare()
        impactFeedback.impactOccurred()

        // Toggle expansion state with Apple-style animation
        withAnimation(isExpanded ? collapseAnimation : expandAnimation) {
            isExpanded.toggle()
        }

        // Manage content appearance with staggered timing
        if isExpanded {
            // When expanding, show content after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showContent = true
                }
            }
        } else {
            // When collapsing, hide content immediately
            withAnimation(.easeOut(duration: 0.2)) {
                showContent = false
            }
        }

        // Start fetching when expanded
        if !isExpanded, let parentId = parentId {
            triggerParentFetch(parentId: parentId)
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

// Enhanced skeleton loading state with liquid glass shimmer effects
struct ParentPostSkeleton: View {
    @State private var shimmerOffset: CGFloat = -200
    @Environment(\.isLiquidGlassEnabled) private var isLiquidGlassEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Avatar skeleton with liquid glass shimmer effect
                Circle()
                    .fill(Color(.systemBackground))
                    .overlay(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.clear,
                                        Color.white.opacity(0.4),
                                        Color.clear,
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .offset(x: shimmerOffset)
                            .clipped()
                    )
                    .advancedLiquidGlass(
                        variant: .clear, intensity: 0.6, morphingState: .transitioning)

                VStack(alignment: .leading, spacing: 4) {
                    // Username skeleton with liquid glass
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.ultraThinMaterial)
                        )
                        .frame(width: 85, height: 14)
                        .advancedLiquidGlass(
                            variant: .clear, intensity: 0.5, morphingState: .transitioning)

                    // Handle skeleton with liquid glass
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.ultraThinMaterial)
                        )
                        .frame(width: 65, height: 11)
                        .advancedLiquidGlass(
                            variant: .clear, intensity: 0.4, morphingState: .transitioning)
                }

                Spacer()

                // Time skeleton with liquid glass
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.ultraThinMaterial)
                    )
                    .frame(width: 35, height: 11)
                    .advancedLiquidGlass(
                        variant: .clear, intensity: 0.4, morphingState: .transitioning)
            }

            // Content skeleton with varied widths and liquid glass effects
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.ultraThinMaterial)
                    )
                    .frame(height: 14)
                    .advancedLiquidGlass(
                        variant: .clear, intensity: 0.5, morphingState: .transitioning)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.ultraThinMaterial)
                    )
                    .frame(width: 220, height: 14)
                    .advancedLiquidGlass(
                        variant: .clear, intensity: 0.4, morphingState: .transitioning)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.ultraThinMaterial)
                    )
                    .frame(width: 160, height: 14)
                    .advancedLiquidGlass(
                        variant: .clear, intensity: 0.3, morphingState: .transitioning)
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
        .enableLiquidGlass()
        .previewLayout(.sizeThatFits)
    }
}
