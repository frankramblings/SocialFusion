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

    func isFetching(id: String, platform: SocialPlatform) -> Bool {
        let cacheKey = "\(platform.rawValue):\(id)"
        return fetching.contains(cacheKey)
    }

    func getCachedPost(id: String) -> Post? {
        return cache[id]
    }

    func getParentPost(for post: Post) -> Post? {
        guard let parentId = post.inReplyToID else { return nil }
        let cacheKey = "\(post.platform.rawValue):\(parentId)"
        return cache[cacheKey]
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
        // Use the same cache key format as SocialServiceManager
        let cacheKey = "\(platform.rawValue):\(id)"
        guard !fetching.contains(cacheKey) else { return }
        fetching.insert(cacheKey)

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
                    self.fetching.remove(cacheKey)
                    if let post = post {
                        self.cache[cacheKey] = post
                    }
                }
            } catch {
                await MainActor.run {
                    self.fetching.remove(cacheKey)
                }
            }
        }
    }
}

struct ExpandingReplyBanner: View {
    // MARK: - Properties
    let username: String
    let network: SocialPlatform
    let parentId: String?
    let initialParent: Post?  // Add optional initial parent post
    @Binding var isExpanded: Bool
    let onBannerTap: (() -> Void)?
    let onParentPostTap: ((Post) -> Void)?

    // MARK: - State
    @State private var parent: Post?
    @State private var showContent = false
    @State private var fetchAttempted = false
    @State private var isLoading = false
    @State private var fetchError: String?

    // MARK: - Environment
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @Environment(\.isLiquidGlassEnabled) private var isLiquidGlassEnabled

    // Use the shared PostParentCache instance
    private var parentCache: PostParentCache { PostParentCache.shared }

    // Enhanced animation state management
    @State private var isPressed = false
    @State private var contentHeight: CGFloat = 0

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
        // Priority 1: Use the real display name from the fetched parent post if available
        if let parent = parent {
            // Use display name (real name) if available and not empty
            if !parent.authorName.isEmpty && parent.authorName != "unknown"
                && parent.authorName != "Loading..." && !parent.isPlaceholder
            {
                return parent.authorName
            }
            // Use username without @ symbol if display name not available
            if !parent.authorUsername.isEmpty && parent.authorUsername != "unknown.bsky.social"
                && parent.authorUsername != "unknown" && !parent.isPlaceholder
            {
                return parent.authorUsername.hasPrefix("@")
                    ? String(parent.authorUsername.dropFirst()) : parent.authorUsername
            }
        }

        // Priority 2: Check cache for parent post even if we don't have it in state yet
        if let parentId = parentId {
            let cacheKey = "\(network.rawValue):\(parentId)"
            if let cachedParent = parentCache.getCachedPost(id: cacheKey) {
                // Use cached parent info
                if !cachedParent.authorName.isEmpty && cachedParent.authorName != "unknown"
                    && cachedParent.authorName != "Loading..." && !cachedParent.isPlaceholder
                {
                    return cachedParent.authorName
                }
                if !cachedParent.authorUsername.isEmpty
                    && cachedParent.authorUsername != "unknown.bsky.social"
                    && cachedParent.authorUsername != "unknown" && !cachedParent.isPlaceholder
                {
                    return cachedParent.authorUsername.hasPrefix("@")
                        ? String(cachedParent.authorUsername.dropFirst())
                        : cachedParent.authorUsername
                }
            }
        }

        // Priority 3: Check if the username is a generic fallback (like "user-frwkc7fg")
        // ONLY show "someone" for these truly generic cases AND we don't have cached data
        if username.hasPrefix("user-") && username.count == 13 {
            // This is likely a generic DID-based username from Bluesky fallback
            return "someone"
        }

        // Priority 4: For normal usernames (even if not in cache), show the actual username
        // Remove @ if present for cleaner display
        let cleanUsername = username.hasPrefix("@") ? String(username.dropFirst()) : username
        return cleanUsername
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

                    Text("Replying to \(displayUsername)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    }

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
                .contentShape(Rectangle())
                .scaleEffect(isPressed ? 0.98 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)
            }
            .buttonStyle(PlainButtonStyle())
            .onLongPressGesture(
                minimumDuration: 0, maximumDistance: .infinity,
                pressing: { pressing in
                    // Remove animation to prevent floating
                    isPressed = pressing
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
                } else if isLoading {
                    // Skeleton loading state while fetching
                    ParentPostSkeleton()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                } else if let error = fetchError {
                    // Error state with retry option
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                            .font(.title2)
                        Text("Unable to load parent post")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Retry") {
                            fetchAttempted = false
                            fetchError = nil
                            if let parentId = parentId {
                                triggerParentFetch(parentId: parentId)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                } else if isExpanded {
                    // Placeholder content when expanded but no parent data available
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("@\(username)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                Text("Original post")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }

                        Text("Tap to view the original post this is replying to")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Try to fetch the parent post when placeholder is tapped
                        if let parentId = parentId {
                            triggerParentFetch(parentId: parentId)
                        }
                    }
                }
            }
            .opacity(showContent ? 1 : 0)
            .scaleEffect(showContent ? 1 : 0.98, anchor: .top)
            .frame(height: isExpanded ? nil : 0)
            .clipped()
            .animation(isExpanded ? expandAnimation : collapseAnimation, value: showContent)
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
                        ? AnyShapeStyle(Color.clear)  // Remove gray background, let liquid glass work directly
                        : AnyShapeStyle(Color.clear)
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
        .background(
            // Apply liquid glass effect only when expanded
            Group {
                if isExpanded {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.clear)
                        .advancedLiquidGlass(
                            variant: liquidGlassVariant,
                            intensity: 0.9,
                            morphingState: liquidGlassMorphingState
                        )
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 20 : 12, style: .continuous))
        .onAppear {
            // Check for proactively fetched parent posts with retry mechanism
            Task { @MainActor in
                guard let parentId = parentId else { return }

                let cacheKey = "\(network.rawValue):\(parentId)"
                print(
                    "🔍 ExpandingReplyBanner: Checking cache for parent \(parentId) with key: \(cacheKey)"
                )

                // Try to find cached parent post with retries to account for background fetching
                for attempt in 1...5 {
                    if let cachedPost = parentCache.getCachedPost(id: cacheKey) {
                        parent = cachedPost
                        print(
                            "✅ ExpandingReplyBanner: Found cached parent on attempt \(attempt): \(cachedPost.authorUsername)"
                        )
                        return
                    }

                    // Wait a bit longer on each attempt to give background fetching time
                    let delay = UInt64(attempt * 200_000_000)  // 0.2s, 0.4s, 0.6s, 0.8s, 1.0s
                    try? await Task.sleep(nanoseconds: delay)
                    print(
                        "🔄 ExpandingReplyBanner: Cache check attempt \(attempt) failed, retrying..."
                    )
                }

                print(
                    "❌ ExpandingReplyBanner: No cached parent found after 5 attempts for key: \(cacheKey)"
                )
                // Fallback fetching will be triggered when user expands the banner
            }
        }
        .onChange(of: isExpanded) { newValue in
            // Animate showContent state synchronization with expansion
            withAnimation(newValue ? expandAnimation : collapseAnimation) {
                showContent = newValue
            }
        }
    }

    private func handleBannerTap() {
        // Provide refined haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.prepare()
        impactFeedback.impactOccurred()

        // Animate the expansion state change with streamlined animation
        withAnimation(isExpanded ? collapseAnimation : expandAnimation) {
            isExpanded.toggle()
        }

        // Only start fetching when expanded if we don't already have the parent data
        if isExpanded, let parentId = parentId, parent == nil {
            print("🔄 Triggering fetch from banner tap")
            triggerParentFetch(parentId: parentId)
        }

        onBannerTap?()
    }

    private func triggerParentFetch(parentId: String) {
        // Skip if already loading, attempted, or if we already have the parent
        guard !isLoading && !fetchAttempted && parent == nil else {
            print(
                "⏭️ Skipping fetch - already loading: \(isLoading), attempted: \(fetchAttempted), has parent: \(parent != nil)"
            )
            return
        }

        // Use Task to defer the fetch outside view rendering cycle
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds

            isLoading = true
            fetchAttempted = true
            fetchError = nil

            do {
                let fetchedPost: Post?

                switch network {
                case .bluesky:
                    // Use the serviceManager's Bluesky post fetching method
                    fetchedPost = try await serviceManager.fetchBlueskyPostByID(parentId)

                case .mastodon:
                    // For Mastodon, we need to find an appropriate account
                    guard let mastodonAccount = serviceManager.mastodonAccounts.first else {
                        throw ServiceError.invalidAccount(reason: "No Mastodon account available")
                    }
                    fetchedPost = try await serviceManager.fetchMastodonStatus(
                        id: parentId, account: mastodonAccount)
                }

                if let post = fetchedPost {
                    parent = post
                    // Use the same cache key format as SocialServiceManager
                    let cacheKey = "\(network.rawValue):\(parentId)"
                    parentCache.cache[cacheKey] = post
                    print(
                        "✅ Fetched parent post: \(post.authorUsername) - \(post.content.prefix(50))..."
                    )
                } else {
                    fetchError = "Post not found"
                    print("❌ Parent post not found for ID: \(parentId)")
                }

            } catch {
                fetchError = error.localizedDescription
                print("❌ Fetch error: \(error.localizedDescription)")
            }

            isLoading = false
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
            // Use Task to defer state updates outside view rendering cycle
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
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
}

struct ExpandingReplyBanner_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Bluesky reply banner
            ExpandingReplyBanner(
                username: "testuser",
                network: .bluesky,
                parentId: nil,
                initialParent: nil,
                isExpanded: .constant(false),
                onBannerTap: nil,
                onParentPostTap: nil
            )

            // Mastodon reply banner
            ExpandingReplyBanner(
                username: "testuser",
                network: .mastodon,
                parentId: nil,
                initialParent: nil,
                isExpanded: .constant(true),
                onBannerTap: nil,
                onParentPostTap: nil
            )
        }
        .padding()
        .enableLiquidGlass()
        .previewLayout(.sizeThatFits)
    }
}
