import SwiftUI

/// Profile header component displaying banner, avatar, bio, fields, and stats.
/// Designed for reuse across Mastodon and Bluesky profile screens.
struct ProfileHeaderView: View {
  let profile: UserProfile
  let isOwnProfile: Bool
  var onEditProfile: (() -> Void)?
  var relationshipState: (isFollowing: Bool, isFollowedBy: Bool, isMuting: Bool, isBlocking: Bool)?
  var onFollow: (() -> Void)?
  var onUnfollow: (() -> Void)?
  var onMute: (() -> Void)?
  var onUnmute: (() -> Void)?
  var onBlock: (() -> Void)?
  var onUnblock: (() -> Void)?

  @State private var bioExpanded = false
  @State private var showFollowingMenu = false
  @State private var showBlockConfirmation = false

  // MARK: - Constants

  private enum Layout {
    static let bannerHeight: CGFloat = 200
    static let avatarSize: CGFloat = 72
    static let avatarBorderWidth: CGFloat = 3
    static let avatarOverlap: CGFloat = 24
    static let badgeSize: CGFloat = 24
    static let horizontalPadding: CGFloat = 16
    static let bioLineLimit = 6
    static let fieldCornerRadius: CGFloat = 10
  }

  // MARK: - Body

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      bannerSection
      avatarRow
        .padding(.top, -Layout.avatarOverlap)
      identitySection
      bioSection
      fieldsSection
      statsRow
    }
  }

  // MARK: - Banner

  private var bannerSection: some View {
    GeometryReader { geo in
      let minY = geo.frame(in: .named("profileScroll")).minY
      let offset = minY > 0 ? -minY * 0.5 : 0
      let height = minY > 0 ? Layout.bannerHeight + minY : Layout.bannerHeight

      ZStack {
        if let headerURLString = profile.headerURL,
           let headerURL = URL(string: headerURLString) {
          CachedAsyncImage(url: headerURL, priority: .high) { image in
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: geo.size.width, height: height)
              .clipped()
          } placeholder: {
            bannerGradient
              .frame(width: geo.size.width, height: height)
          }
        } else {
          bannerGradient
            .frame(width: geo.size.width, height: height)
        }
      }
      .offset(y: offset)
    }
    .frame(height: Layout.bannerHeight)
    .accessibilityHidden(true)
  }

  private var bannerGradient: some View {
    LinearGradient(
      colors: platformGradientColors,
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private var platformGradientColors: [Color] {
    switch profile.platform {
    case .mastodon:
      return [Color.mastodonColor.opacity(0.8), Color.mastodonColor.opacity(0.4)]
    case .bluesky:
      return [Color.blueskyColor.opacity(0.8), Color.blueskyColor.opacity(0.4)]
    }
  }

  // MARK: - Avatar Row

  private var avatarRow: some View {
    HStack(alignment: .bottom, spacing: 12) {
      avatarView
      Spacer()
      actionButton
        .padding(.bottom, 4)
    }
    .padding(.horizontal, Layout.horizontalPadding)
  }

  private var avatarView: some View {
    ZStack(alignment: .bottomTrailing) {
      if let avatarURLString = profile.avatarURL,
         let avatarURL = URL(string: avatarURLString) {
        CachedAsyncImage(url: avatarURL, priority: .high) { image in
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: Layout.avatarSize, height: Layout.avatarSize)
            .clipShape(Circle())
        } placeholder: {
          avatarPlaceholder
        }
      } else {
        avatarPlaceholder
      }
    }
    .frame(width: Layout.avatarSize, height: Layout.avatarSize)
    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: Layout.avatarBorderWidth))
    .overlay(alignment: .bottomTrailing) {
      PlatformLogoBadge(
        platform: profile.platform,
        size: Layout.badgeSize,
        shadowEnabled: true
      )
      .offset(x: 2, y: 2)
    }
    .accessibilityLabel("\(profile.displayName ?? profile.username)'s profile picture")
  }

  private var avatarPlaceholder: some View {
    Circle()
      .fill(
        LinearGradient(
          colors: [profile.platform.swiftUIColor.opacity(0.6), profile.platform.swiftUIColor.opacity(0.3)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .frame(width: Layout.avatarSize, height: Layout.avatarSize)
      .overlay {
        let initials = PostAuthorImageView.generateInitials(from: profile.displayName ?? profile.username)
        if !initials.isEmpty {
          Text(initials)
            .font(.system(size: Layout.avatarSize * 0.4, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
        } else {
          Image(systemName: "person.fill")
            .foregroundColor(.white.opacity(0.8))
            .font(.system(size: Layout.avatarSize * 0.4))
        }
      }
  }

  // MARK: - Action Button

  @ViewBuilder
  private var actionButton: some View {
    if isOwnProfile {
      Button(action: { onEditProfile?() }) {
        Text("Edit Profile")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.primary)
          .padding(.horizontal, 20)
          .padding(.vertical, 10)
          .background(Color(.secondarySystemBackground))
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
    } else if let state = relationshipState {
      VStack(alignment: .trailing, spacing: 6) {
        if state.isBlocking {
          blockedButton
        } else if state.isFollowing {
          followingButton(isMuting: state.isMuting)
        } else {
          followButton
        }
        relationshipBadge
      }
    }
  }

  private var blockedButton: some View {
    Button(action: { onUnblock?() }) {
      HStack(spacing: 6) {
        Image(systemName: "hand.raised.fill")
          .font(.system(size: 12))
        Text("Blocked")
          .font(.subheadline)
          .fontWeight(.semibold)
      }
      .foregroundColor(.red)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(Color.red.opacity(0.1))
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  private func followingButton(isMuting: Bool) -> some View {
    Menu {
      Button(role: .destructive, action: { onUnfollow?() }) {
        Label("Unfollow", systemImage: "person.badge.minus")
      }
      Divider()
      if isMuting {
        Button(action: { onUnmute?() }) {
          Label("Unmute", systemImage: "speaker")
        }
      } else {
        Button(action: { onMute?() }) {
          Label("Mute", systemImage: "speaker.slash")
        }
      }
      Button(role: .destructive, action: { showBlockConfirmation = true }) {
        Label("Block", systemImage: "hand.raised")
      }
    } label: {
      Text("Following")
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundColor(.primary)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }
    .confirmationDialog(
      "Block this user?",
      isPresented: $showBlockConfirmation,
      titleVisibility: .visible
    ) {
      Button("Block", role: .destructive) {
        onBlock?()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("They won't be able to follow you or see your posts.")
    }
  }

  private var followButton: some View {
    Button(action: { onFollow?() }) {
      Text("Follow")
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.accentColor)
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var relationshipBadge: some View {
    if let state = relationshipState {
      if state.isFollowing && state.isFollowedBy {
        Text("Mutuals")
          .font(.caption)
          .fontWeight(.medium)
          .foregroundColor(.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Color(.secondarySystemBackground))
          .clipShape(Capsule())
      } else if state.isFollowedBy {
        Text("Follows you")
          .font(.caption)
          .fontWeight(.medium)
          .foregroundColor(.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Color(.secondarySystemBackground))
          .clipShape(Capsule())
      }
    }
  }

  // MARK: - Identity

  private var identitySection: some View {
    VStack(alignment: .leading, spacing: 2) {
      EmojiDisplayNameText(
        profile.displayName ?? profile.username,
        emojiMap: profile.displayNameEmojiMap,
        font: .title2,
        fontWeight: .bold,
        foregroundColor: .primary,
        lineLimit: 2
      )

      Text("@\(profile.username)")
        .font(.subheadline)
        .foregroundColor(.secondary)
        .lineLimit(1)
    }
    .padding(.horizontal, Layout.horizontalPadding)
    .padding(.top, 8)
  }

  // MARK: - Bio

  @ViewBuilder
  private var bioSection: some View {
    if let bio = profile.bio, !bio.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        bioContent(bio)
          .lineLimit(bioExpanded ? nil : Layout.bioLineLimit)

        if !bioExpanded {
          Button(action: { withAnimation(.easeInOut(duration: 0.2)) { bioExpanded = true } }) {
            Text("Show more")
              .font(.subheadline)
              .foregroundColor(.accentColor)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, Layout.horizontalPadding)
      .padding(.top, 8)
    }
  }

  @ViewBuilder
  private func bioContent(_ bio: String) -> some View {
    if profile.platform == .mastodon {
      // Mastodon bios are HTML — parse asynchronously to avoid AttributeGraph crash
      AsyncHTMLText(html: bio, font: .subheadline, foregroundColor: .primary)
    } else {
      // Bluesky bios are plain text
      Text(bio)
        .font(.subheadline)
        .foregroundColor(.primary)
    }
  }

  // MARK: - Fields (Mastodon)

  @ViewBuilder
  private var fieldsSection: some View {
    if let fields = profile.fields, !fields.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
          if index > 0 {
            Divider()
              .padding(.horizontal, 12)
          }
          fieldRow(field)
        }
      }
      .background(Color(.secondarySystemBackground))
      .clipShape(RoundedRectangle(cornerRadius: Layout.fieldCornerRadius))
      .padding(.horizontal, Layout.horizontalPadding)
      .padding(.top, 12)
    }
  }

  private func fieldRow(_ field: ProfileField) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text(field.name)
        .font(.caption)
        .fontWeight(.medium)
        .foregroundColor(.secondary)
        .frame(width: 90, alignment: .leading)

      Spacer(minLength: 0)

      HStack(spacing: 4) {
        if field.isVerified {
          Image(systemName: "checkmark.seal.fill")
            .font(.caption2)
            .foregroundColor(.green)
        }

        // Field values may contain HTML links (Mastodon) — parse asynchronously
        AsyncHTMLText(html: field.value, font: .caption, foregroundColor: .primary, lineLimit: 1)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(fieldAccessibilityLabel(field))
  }

  private func fieldAccessibilityLabel(_ field: ProfileField) -> String {
    let strippedValue = field.value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    if field.isVerified {
      return "\(field.name), \(strippedValue), verified"
    } else {
      return "\(field.name), \(strippedValue)"
    }
  }

  // MARK: - Stats

  private var statsRow: some View {
    HStack(spacing: 16) {
      statItem(count: profile.statusesCount, label: "Posts")
      statItem(count: profile.followingCount, label: "Following")
      statItem(count: profile.followersCount, label: "Followers")
      Spacer()
    }
    .padding(.horizontal, Layout.horizontalPadding)
    .padding(.top, 12)
    .padding(.bottom, 8)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(profile.statusesCount) posts, \(profile.followingCount) following, \(profile.followersCount) followers")
  }

  private func statItem(count: Int, label: String) -> some View {
    HStack(spacing: 4) {
      Text(Self.formatCount(count))
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundColor(.primary)
      Text(label)
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
  }

  // MARK: - Helpers

  /// Formats a count with K/M suffix for large numbers
  static func formatCount(_ count: Int) -> String {
    if count >= 1_000_000 {
      let value = Double(count) / 1_000_000.0
      return value.truncatingRemainder(dividingBy: 1) == 0
        ? "\(Int(value))M"
        : String(format: "%.1fM", value)
    } else if count >= 1_000 {
      let value = Double(count) / 1_000.0
      return value.truncatingRemainder(dividingBy: 1) == 0
        ? "\(Int(value))K"
        : String(format: "%.1fK", value)
    }
    return "\(count)"
  }
}

// MARK: - Preview

// MARK: - Async HTML Text

/// Renders HTML content asynchronously to avoid AttributeGraph crashes.
/// Shows plain text immediately, swaps in parsed AttributedString once ready.
private struct AsyncHTMLText: View {
  let html: String
  var font: Font = .subheadline
  var foregroundColor: Color = .primary
  var lineLimit: Int? = nil

  @State private var attributedString: AttributedString?

  var body: some View {
    Group {
      if let attributed = attributedString {
        Text(attributed)
      } else {
        Text(plainText)
      }
    }
    .font(font)
    .foregroundColor(foregroundColor)
    .lineLimit(lineLimit)
    .task(id: html) {
      let htmlString = HTMLString(raw: html)
      let result = await Task.detached(priority: .userInitiated) {
        await EmojiTextApp.buildAttributedString(
          htmlString: htmlString,
          font: .subheadline,
          foregroundColor: .primary,
          mentions: [],
          tags: []
        )
      }.value
      attributedString = result
    }
  }

  private var plainText: String {
    html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&nbsp;", with: " ")
  }
}

#Preview("Mastodon Profile") {
  ScrollView {
    ProfileHeaderView(
      profile: UserProfile(
        id: "1",
        username: "manton@mastodon.social",
        displayName: "Manton Reece",
        avatarURL: "https://files.mastodon.social/accounts/avatars/000/000/001/original/avatar.png",
        headerURL: nil,
        bio: "<p>Building <a href=\"https://micro.blog\">Micro.blog</a>. Author of Indie Microblogging. Podcaster.</p>",
        followersCount: 12500,
        followingCount: 842,
        statusesCount: 34200,
        platform: .mastodon,
        following: true,
        followedBy: true,
        fields: [
          ProfileField(name: "Website", value: "<a href=\"https://manton.org\">manton.org</a>", isVerified: true),
          ProfileField(name: "Pronouns", value: "he/him"),
          ProfileField(name: "Location", value: "Austin, TX"),
        ],
        displayNameEmojiMap: nil
      ),
      isOwnProfile: false,
      relationshipState: (isFollowing: true, isFollowedBy: true, isMuting: false, isBlocking: false),
      onFollow: {},
      onUnfollow: {},
      onMute: {},
      onUnmute: {},
      onBlock: {},
      onUnblock: {}
    )
  }
  .coordinateSpace(name: "profileScroll")
}

#Preview("Bluesky Profile") {
  ScrollView {
    ProfileHeaderView(
      profile: UserProfile(
        id: "2",
        username: "jay.bsky.team",
        displayName: "Jay Graber",
        avatarURL: nil,
        headerURL: nil,
        bio: "CEO of Bluesky. Building decentralized social media.",
        followersCount: 258000,
        followingCount: 1200,
        statusesCount: 4500,
        platform: .bluesky
      ),
      isOwnProfile: false,
      relationshipState: (isFollowing: false, isFollowedBy: false, isMuting: false, isBlocking: false),
      onFollow: {},
      onUnfollow: {}
    )
  }
  .coordinateSpace(name: "profileScroll")
}

#Preview("Own Profile") {
  ScrollView {
    ProfileHeaderView(
      profile: UserProfile(
        id: "3",
        username: "frank@mastodon.social",
        displayName: "Frank",
        avatarURL: nil,
        headerURL: nil,
        bio: "Making things.",
        followersCount: 350,
        followingCount: 200,
        statusesCount: 1240,
        platform: .mastodon
      ),
      isOwnProfile: true,
      onEditProfile: { print("Edit profile tapped") }
    )
  }
  .coordinateSpace(name: "profileScroll")
}
