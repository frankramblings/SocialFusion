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
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.2)) {
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
                        .background(Color(.systemGray6).opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.secondary.opacity(0.08), lineWidth: 0.5)
                        )
                        .padding(.top, 8)
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
                        .background(Color(.systemGray6).opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.secondary.opacity(0.08), lineWidth: 0.5)
                        )
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
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6).opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.secondary.opacity(0.08), lineWidth: 0.5)
                    )
                    .padding(.top, 8)
                }
            }
        }
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
