import Foundation

/// Unified model for autocomplete suggestions (mentions/hashtags/emoji)
/// Note: Not Codable due to EntityPayload containing [String: Any]
/// Persistence uses simplified JSON serialization (IDs and display text only)
public struct AutocompleteSuggestion: Identifiable, Equatable {
  /// Stable ID (not UUID) for caching/dedupe:
  /// - Mastodon: account id or `acct@host`
  /// - Bluesky: DID
  /// - Hashtags: normalized tag string
  /// - Emoji: shortcode/unicode
  public let id: String
  
  /// Display text (e.g., "@handle" or "#tag")
  public let displayText: String
  
  /// Subtitle (e.g., display name for mentions)
  public let subtitle: String?
  
  /// Which networks this suggestion applies to
  public let platforms: Set<SocialPlatform>
  
  /// Platform-specific payloads
  public let entityPayload: EntityPayload
  
  /// From recent cache
  public let isRecent: Bool
  
  /// User follows this account (for mentions)
  public let isFollowed: Bool
  
  /// Avatar URL (for mentions)
  public let avatarURL: String?
  
  public init(
    id: String,
    displayText: String,
    subtitle: String? = nil,
    platforms: Set<SocialPlatform>,
    entityPayload: EntityPayload,
    isRecent: Bool = false,
    isFollowed: Bool = false,
    avatarURL: String? = nil
  ) {
    self.id = id
    self.displayText = displayText
    self.subtitle = subtitle
    self.platforms = platforms
    self.entityPayload = entityPayload
    self.isRecent = isRecent
    self.isFollowed = isFollowed
    self.avatarURL = avatarURL
  }
  
  /// Create from SearchUser (for mentions)
  public static func from(searchUser: SearchUser, isRecent: Bool = false, isFollowed: Bool = false) -> AutocompleteSuggestion {
    let stableId: String
    if searchUser.platform == .bluesky && searchUser.id.hasPrefix("did:") {
      stableId = searchUser.id // DID
    } else if searchUser.platform == .mastodon {
      stableId = searchUser.id // Account ID or acct@host
    } else {
      stableId = searchUser.username
    }
    
    let payloadData: [String: Any]
    if searchUser.platform == .bluesky {
      payloadData = [
        "did": searchUser.id,
        "handle": searchUser.username,
        "displayName": searchUser.displayName ?? ""
      ]
    } else {
      payloadData = [
        "accountId": searchUser.id,
        "acct": searchUser.username,
        "displayName": searchUser.displayName ?? ""
      ]
    }
    
    return AutocompleteSuggestion(
      id: stableId,
      displayText: "@\(searchUser.username)",
      subtitle: searchUser.displayName,
      platforms: [searchUser.platform],
      entityPayload: EntityPayload(platform: searchUser.platform, data: payloadData),
      isRecent: isRecent,
      isFollowed: isFollowed,
      avatarURL: searchUser.avatarURL
    )
  }
  
  /// Create from SearchTag (for hashtags)
  public static func from(searchTag: SearchTag, isRecent: Bool = false) -> AutocompleteSuggestion {
    let normalizedTag = searchTag.name.lowercased()
    return AutocompleteSuggestion(
      id: normalizedTag,
      displayText: "#\(searchTag.name)",
      subtitle: nil,
      platforms: [searchTag.platform],
      entityPayload: EntityPayload(platform: searchTag.platform, data: ["tag": normalizedTag]),
      isRecent: isRecent
    )
  }
}
