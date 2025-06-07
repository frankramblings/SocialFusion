import SwiftUI

struct ExpandingReplyBanner: View {
    let username: String
    let network: SocialPlatform
    let parentId: String?
    @Binding var isExpanded: Bool
    var onBannerTap: (() -> Void)? = nil
    @ObservedObject private var parentCache = PostParentCache.shared
    @State private var parent: Post? = nil
    @State private var fetchAttempted = false

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Banner row with improved tap handling
            Button(action: {
                // Provide haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()

                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }

                // Start fetching when expanded
                if isExpanded, let parentId = parentId {
                    triggerParentFetch(parentId: parentId)
                }

                onBannerTap?()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.up.left")
                        .font(.caption)
                        .foregroundColor(platformColor)

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
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            // Parent post preview with skeleton loading state
            if isExpanded {
                Group {
                    if let parent = parent, !parent.isPlaceholder {
                        // Real parent post content
                        ParentPostPreview(post: parent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                    removal: .opacity
                                ))
                    } else if shouldShowLoadingState {
                        // Skeleton loading state to prevent layout shifts
                        ParentPostSkeleton()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .transition(.opacity)
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
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(isExpanded ? Color(.systemGray6) : Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        .onReceive(parentCache.$cache) { cache in
            guard let parentId = parentId else { return }
            let newParent = cache[parentId]
            if parent !== newParent {
                // Defer the state update to the next runloop cycle to prevent AttributeGraph cycles
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        parent = newParent
                    }
                }
            }
        }
        .onAppear {
            // Defer initial setup to prevent state modification during view rendering
            DispatchQueue.main.async {
                // Set initial parent from cache
                if let parentId = parentId {
                    parent = parentCache.getCachedPost(id: parentId)

                    // Preload in background for smoother experience
                    if !parentCache.isFetching(id: parentId) && parent == nil {
                        triggerBackgroundPreload(parentId: parentId)
                    }
                }
            }
        }
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

// Skeleton loading state to prevent layout shifts
struct ParentPostSkeleton: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Avatar skeleton
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    // Username skeleton
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 12)

                    // Handle skeleton
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 60, height: 10)
                }

                Spacer()

                // Time skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 40, height: 10)
            }

            // Content skeleton
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 12)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 180, height: 12)
            }
            .padding(.leading, 4)
        }
        .opacity(isAnimating ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear {
            isAnimating = true
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
