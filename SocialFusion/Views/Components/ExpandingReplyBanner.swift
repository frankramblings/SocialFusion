import SwiftUI

struct ExpandingReplyBanner: View {
    let username: String
    let network: SocialPlatform
    let parentId: String?
    @Binding var isExpanded: Bool
    var onBannerTap: (() -> Void)? = nil
    @ObservedObject private var parentCache = PostParentCache.shared

    // Track when we've attempted to fetch the parent
    @State private var hasFetched = false

    private var parent: Post? {
        guard let parentId = parentId else { return nil }
        let cachedParent = parentCache.cache[parentId]
        if let cachedParent = cachedParent {
            print(
                "[DEBUG] ExpandingReplyBanner found cached parent for \(parentId): authorUsername='\(cachedParent.authorUsername)', isPlaceholder=\(cachedParent.isPlaceholder)"
            )
        }
        return cachedParent
    }

    // Use the actual parent username if available, otherwise fall back to the provided username
    private var displayUsername: String {
        if let parent = parent {
            // Use cached parent username if it's valid and not a placeholder
            if !parent.authorUsername.isEmpty && parent.authorUsername != "unknown.bsky.social"
                && parent.authorUsername != "unknown" && !parent.isPlaceholder
            {
                print(
                    "[DEBUG] ExpandingReplyBanner using cached parent username: \(parent.authorUsername)"
                )
                return parent.authorUsername
            }
        }

        print(
            "[DEBUG] ExpandingReplyBanner using fallback username: \(username), parent exists: \(parent != nil), parent username: '\(parent?.authorUsername ?? "nil")', isExpanded: \(isExpanded), hasFetched: \(hasFetched)"
        )
        return username
    }

    private var shouldShowLoadingState: Bool {
        guard let parentId = parentId else { return false }
        return isExpanded && parentCache.isFetching(parentId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Banner row
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.up.left")
                    .font(.caption)
                    .foregroundColor(network.secondaryColor)

                Text("Replying to @\(displayUsername)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Show a subtle loading indicator if actively fetching
                if shouldShowLoadingState {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                }

                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                print(
                    "[DEBUG] ExpandingReplyBanner tapped for postID: \(parentId ?? "nil"), username: \(displayUsername), parent present: \(parent != nil), isExpanded: \(isExpanded)"
                )
                if let parent = parent {
                    print("[DEBUG] Parent postID: \(parent.id), author: \(parent.authorUsername)")
                }

                withAnimation(.spring(response: 0.5, dampingFraction: 0.85, blendDuration: 0.25)) {
                    isExpanded.toggle()
                }
                onBannerTap?()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray6).opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.08), lineWidth: 0.5)
            )
            .zIndex(1)

            // Parent post preview
            if isExpanded {
                if let parent = parent {
                    #if DEBUG
                        print(
                            "[DEBUG] ExpandingReplyBanner: parent.id=\(parent.id), isPlaceholder=\(parent.isPlaceholder)"
                        )
                    #endif
                    if parent.isPlaceholder {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.secondary)
                                .font(.title2)
                            Text("Loading parent post...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                    } else {
                        ParentPostPreview(post: parent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray6).opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.08), lineWidth: 0.5)
                            )
                            .padding(.top, 8)
                    }
                } else if shouldShowLoadingState {
                    LoadingParentView()
                        .padding(.top, 8)
                } else if hasFetched {
                    // Show error state if we've tried fetching but have no parent
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                            .font(.title2)
                        Text("Unable to load parent post")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                } else {
                    LoadingParentView()
                        .padding(.top, 8)
                }
            }
        }
        .onChange(of: isExpanded) { newValue in
            // Trigger parent hydration when expanded
            if newValue, let parentId = parentId {
                triggerParentFetch(parentId: parentId)
            }
        }
        .onAppear {
            // Also try to fetch immediately if expanded
            if isExpanded, let parentId = parentId {
                triggerParentFetch(parentId: parentId)
            }
        }
    }

    private func triggerParentFetch(parentId: String) {
        print("[DEBUG] ExpandingReplyBanner triggering parent fetch for: \(parentId)")

        // Only fetch if we don't have a proper parent already and we're not already fetching
        if (parent == nil || parent?.isPlaceholder == true
            || parent?.authorUsername == "unknown.bsky.social")
            && !parentCache.isFetching(parentId)
        {

            hasFetched = true
            parentCache.fetchRealPost(
                id: parentId,
                username: username,
                platform: network,
                serviceManager: SocialServiceManager.shared,
                allAccounts: SocialServiceManager.shared.mastodonAccounts
                    + SocialServiceManager.shared.blueskyAccounts
            )
        } else if parent != nil {
            // If we already have the parent, mark as fetched
            hasFetched = true
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
