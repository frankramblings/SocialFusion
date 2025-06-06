import SwiftUI

struct ExpandingReplyBanner: View {
    let username: String
    let network: SocialPlatform
    let parentId: String?
    @Binding var isExpanded: Bool
    var onBannerTap: (() -> Void)? = nil
    @ObservedObject private var parentCache = PostParentCache.shared
    @State private var parent: Post? = nil

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
        return isExpanded && parentCache.isFetching(id: parentId)
    }

    @State private var fetchAttempted = false

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
            // Banner row as a button for reliable tap handling
            Button(action: {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85, blendDuration: 0.25)) {
                    isExpanded.toggle()
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
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            // Parent post preview - seamlessly connected to banner
            if isExpanded {
                if let parent = parent {
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
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                    } else {
                        ParentPostPreview(post: parent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .transition(.opacity)
                    }
                } else if shouldShowLoadingState {
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading parent post...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                } else if fetchAttempted {
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
        }
        // Single unified container styling with subtle stroke and background matching post card
        .background(isExpanded ? Color(.systemGray6) : Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .animation(
            .spring(response: 0.5, dampingFraction: 0.85, blendDuration: 0.25), value: isExpanded
        )
        .onAppear {
            print(
                "[ExpandingReplyBanner] onAppear for parentId=\(String(describing: parentId)), isExpanded=\(isExpanded)"
            )
        }
        .onDisappear {
            print("[ExpandingReplyBanner] onDisappear for parentId=\(String(describing: parentId))")
        }
        .onReceive(parentCache.$cache) { cache in
            guard let parentId = parentId else { return }
            let newParent = cache[parentId]
            if parent !== newParent {
                print(
                    "[ExpandingReplyBanner] updateParent for parentId=\(parentId): \(String(describing: newParent))"
                )
                parent = newParent
            }
        }
        .task(id: parentId) {
            guard let parentId = parentId else { return }
            print("[ExpandingReplyBanner] .task for parentId=\(parentId), isExpanded=\(isExpanded)")
            if isExpanded {
                triggerParentFetch(parentId: parentId)
            }
        }
        .onChange(of: isExpanded) { newValue in
            print(
                "[ExpandingReplyBanner] .onChange isExpanded=\(newValue) parentId=\(String(describing: parentId))"
            )
            if newValue, let parentId = parentId {
                triggerParentFetch(parentId: parentId)
            }
        }
    }

    private func triggerParentFetch(parentId: String) {
        print("[ExpandingReplyBanner] triggerParentFetch called for parentId=\(parentId)")
        guard let parent = parent else {
            if !parentCache.isFetching(id: parentId) {
                print("[ExpandingReplyBanner] Actually triggering fetch for parentId=\(parentId)")
                fetchAttempted = true
                parentCache.fetchRealPost(
                    id: parentId,
                    username: username,
                    platform: network,
                    serviceManager: SocialServiceManager.shared,
                    allAccounts: SocialServiceManager.shared.mastodonAccounts
                        + SocialServiceManager.shared.blueskyAccounts
                )
            } else {
                print("[ExpandingReplyBanner] Already fetching parentId=\(parentId)")
            }
            return
        }
        if parent.isPlaceholder, !parentCache.isFetching(id: parentId) {
            print(
                "[ExpandingReplyBanner] Parent is placeholder, triggering fetch for parentId=\(parentId)"
            )
            fetchAttempted = true
            parentCache.fetchRealPost(
                id: parentId,
                username: username,
                platform: network,
                serviceManager: SocialServiceManager.shared,
                allAccounts: SocialServiceManager.shared.mastodonAccounts
                    + SocialServiceManager.shared.blueskyAccounts
            )
        } else {
            print(
                "[ExpandingReplyBanner] Parent is not placeholder or already fetching for parentId=\(parentId)"
            )
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
