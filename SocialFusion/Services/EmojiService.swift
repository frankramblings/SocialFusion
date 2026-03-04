import Foundation

/// Fetches and caches custom emoji from Mastodon instances
public class EmojiService {
  public static let shared = EmojiService(mastodonService: nil)
  
  private var emojiCache: [String: [MastodonEmoji]] = [:] // Key: account ID
  private var recentlyUsed: [String] = [] // Recently used emoji shortcodes
  private let maxRecentlyUsed = 50
  
  public var mastodonService: MastodonService?
  public var accounts: [SocialAccount]
  
  public init(mastodonService: MastodonService?, accounts: [SocialAccount] = []) {
    self.mastodonService = mastodonService
    self.accounts = accounts
  }
  
  /// Fetch custom emoji for an account
  @MainActor
  public func fetchEmoji(for account: SocialAccount) async throws -> [MastodonEmoji] {
    // Check cache first
    if let cached = emojiCache[account.id] {
      return cached
    }
    
    guard let service = mastodonService, account.platform == .mastodon else {
      return []
    }
    
    // Fetch emoji from Mastodon instance
    // Mastodon v3+ has /api/v1/custom_emojis endpoint
    // Try v1 endpoint first (works on v3+ instances), fallback gracefully if not available
    
    guard let serverURL = account.serverURL else {
      return []
    }
    
    // Ensure server URL has scheme
    let serverUrlString = serverURL.absoluteString.contains("://") 
      ? serverURL.absoluteString 
      : "https://\(serverURL.absoluteString)"
    
    guard let emojiURL = URL(string: "\(serverUrlString)/api/v1/custom_emojis") else {
      return []
    }
    
    do {
      // Create authenticated request
      let request = try await service.createAuthenticatedRequest(
        url: emojiURL,
        method: "GET",
        account: account
      )
      
      // Perform request
      let (data, response) = try await URLSession.shared.data(for: request)
      
      guard let httpResponse = response as? HTTPURLResponse else {
        return []
      }
      
      // Handle 404 gracefully (endpoint not available on older instances)
      if httpResponse.statusCode == 404 {
        // Endpoint not available - return empty (no custom emoji)
        emojiCache[account.id] = []
        return []
      }
      
      guard httpResponse.statusCode == 200 else {
        // Other error - return empty
        return []
      }
      
      // Decode emoji list
      let emojis = try JSONDecoder().decode([MastodonEmoji].self, from: data)
      
      // Cache results
      emojiCache[account.id] = emojis
      return emojis
      
    } catch {
      // Network error or decode error - return empty (graceful degradation)
      // Log error for debugging but don't fail
      #if DEBUG
      print("Failed to fetch custom emoji: \(error.localizedDescription)")
      #endif
      emojiCache[account.id] = []
      return []
    }
  }
  
  /// Search emoji by shortcode
  @MainActor
  public func searchEmoji(query: String, account: SocialAccount) async -> [AutocompleteSuggestion] {
    let emojis = try? await fetchEmoji(for: account)
    let queryLower = query.lowercased()
    
    var suggestions: [AutocompleteSuggestion] = []
    
    // Search custom emoji
    if let emojis = emojis {
      for emoji in emojis where emoji.shortcode.lowercased().contains(queryLower) {
        let payload = EntityPayload(platform: .mastodon, data: ["shortcode": emoji.shortcode, "url": emoji.url])
        
        suggestions.append(AutocompleteSuggestion(
          id: emoji.shortcode,
          displayText: ":\(emoji.shortcode):",
          subtitle: nil,
          platforms: [.mastodon],
          entityPayload: payload
        ))
      }
    }
    
    // Search recently used
    for shortcode in recentlyUsed where shortcode.lowercased().contains(queryLower) {
      if !suggestions.contains(where: { $0.id == shortcode }) {
        let payload = EntityPayload(platform: .mastodon, data: ["shortcode": shortcode])
        suggestions.append(AutocompleteSuggestion(
          id: shortcode,
          displayText: ":\(shortcode):",
          subtitle: nil,
          platforms: [.mastodon],
          entityPayload: payload,
          isRecent: true
        ))
      }
    }
    
    // System emoji fallback - search common emoji by name
    let systemEmojiResults = searchSystemEmoji(query: queryLower)
    for emojiResult in systemEmojiResults {
      if !suggestions.contains(where: { $0.id == emojiResult.emoji }) {
        // Create payload for all platforms (system emoji work everywhere)
        let payload = EntityPayload(platform: .mastodon, data: ["unicodeEmoji": emojiResult.emoji])
        suggestions.append(AutocompleteSuggestion(
          id: emojiResult.emoji,
          displayText: emojiResult.emoji, // Actual emoji character, not shortcode
          subtitle: emojiResult.name,
          platforms: [.mastodon, .bluesky], // System emoji work on both platforms
          entityPayload: payload
        ))
      }
    }
    
    return suggestions
  }
  
  /// Search system emoji by name/keyword
  private func searchSystemEmoji(query: String) -> [(emoji: String, name: String)] {
    // Curated list of common emoji with names/keywords
    // This is a basic implementation - could be expanded with full Unicode CLDR data
    let emojiDatabase: [(emoji: String, keywords: [String])] = [
      ("😀", ["grinning", "face", "happy", "smile"]),
      ("😃", ["grinning", "eyes", "happy", "joy"]),
      ("😄", ["grinning", "smiling", "eyes", "happy"]),
      ("😁", ["beaming", "smiling", "eyes", "happy"]),
      ("😅", ["grinning", "sweat", "relieved"]),
      ("😂", ["face", "tears", "joy", "laughing"]),
      ("🤣", ["rolling", "floor", "laughing"]),
      ("😊", ["smiling", "eyes", "blush"]),
      ("😇", ["smiling", "halo", "angel"]),
      ("🙂", ["slightly", "smiling", "face"]),
      ("🙃", ["upside", "down", "face"]),
      ("😉", ["winking", "face"]),
      ("😌", ["relieved", "face"]),
      ("😍", ["heart", "eyes", "love"]),
      ("🥰", ["smiling", "hearts", "love"]),
      ("😘", ["face", "blowing", "kiss"]),
      ("😗", ["kissing", "face"]),
      ("😙", ["kissing", "smiling", "eyes"]),
      ("😚", ["kissing", "closed", "eyes"]),
      ("😋", ["face", "savoring", "food"]),
      ("😛", ["face", "tongue"]),
      ("😝", ["squinting", "tongue"]),
      ("😜", ["winking", "tongue"]),
      ("🤪", ["zany", "face"]),
      ("🤨", ["raised", "eyebrow"]),
      ("🧐", ["monocle", "face"]),
      ("🤓", ["nerd", "face"]),
      ("😎", ["smiling", "sunglasses", "cool"]),
      ("🤩", ["star", "struck"]),
      ("🥳", ["partying", "face", "party"]),
      ("😏", ["smirking", "face"]),
      ("😏", ["smirking", "face"]),
      ("😒", ["unamused", "face"]),
      ("😞", ["disappointed", "face"]),
      ("😔", ["pensive", "face"]),
      ("😟", ["worried", "face"]),
      ("😕", ["confused", "face"]),
      ("🙁", ["slightly", "frowning", "face"]),
      ("😣", ["persevering", "face"]),
      ("😖", ["confounded", "face"]),
      ("😫", ["tired", "face"]),
      ("😩", ["weary", "face"]),
      ("🥺", ["pleading", "face"]),
      ("😢", ["crying", "face"]),
      ("😭", ["loudly", "crying"]),
      ("😤", ["face", "steam", "nose"]),
      ("😠", ["angry", "face"]),
      ("😡", ["pouting", "face"]),
      ("🤬", ["face", "symbols", "mouth"]),
      ("🤯", ["exploding", "head"]),
      ("😳", ["flushed", "face"]),
      ("🥵", ["hot", "face"]),
      ("🥶", ["cold", "face"]),
      ("😱", ["screaming", "face"]),
      ("😨", ["fearful", "face"]),
      ("😰", ["anxious", "sweat"]),
      ("😥", ["sad", "relieved"]),
      ("😓", ["downcast", "sweat"]),
      ("🤗", ["hugging", "face"]),
      ("🤔", ["thinking", "face"]),
      ("🤭", ["face", "hand", "mouth"]),
      ("🤫", ["shushing", "face"]),
      ("🤥", ["lying", "face"]),
      ("😶", ["face", "mouth"]),
      ("😐", ["neutral", "face"]),
      ("😑", ["expressionless", "face"]),
      ("😬", ["grimacing", "face"]),
      ("🙄", ["face", "rolling", "eyes"]),
      ("😯", ["hushed", "face"]),
      ("😦", ["frowning", "open", "mouth"]),
      ("😧", ["anguished", "face"]),
      ("😮", ["face", "open", "mouth"]),
      ("😲", ["astonished", "face"]),
      ("🥱", ["yawning", "face"]),
      ("😴", ["sleeping", "face"]),
      ("🤤", ["drooling", "face"]),
      ("😪", ["sleepy", "face"]),
      ("😵", ["dizzy", "face"]),
      ("🤐", ["zipper", "mouth", "face"]),
      ("🥴", ["woozy", "face"]),
      ("😷", ["face", "medical", "mask"]),
      ("🤒", ["face", "thermometer"]),
      ("🤕", ["face", "bandage"]),
      ("🤢", ["nauseated", "face"]),
      ("🤮", ["face", "vomiting"]),
      ("🤧", ["sneezing", "face"]),
      ("👍", ["thumbs", "up", "like"]),
      ("👎", ["thumbs", "down", "dislike"]),
      ("👌", ["ok", "hand"]),
      ("✌️", ["victory", "hand", "peace"]),
      ("🤞", ["crossed", "fingers"]),
      ("🤟", ["love", "you", "gesture"]),
      ("🤘", ["rock", "on"]),
      ("🤙", ["call", "me", "hand"]),
      ("👏", ["clapping", "hands"]),
      ("🙌", ["raising", "hands"]),
      ("👐", ["open", "hands"]),
      ("🤲", ["palms", "up", "together"]),
      ("🤝", ["handshake"]),
      ("🙏", ["folded", "hands", "pray"]),
      ("✍️", ["writing", "hand"]),
      ("💪", ["flexed", "biceps", "strong"]),
      ("🦵", ["leg"]),
      ("🦶", ["foot"]),
      ("👂", ["ear"]),
      ("🦻", ["ear", "hearing", "aid"]),
      ("👃", ["nose"]),
      ("🧠", ["brain"]),
      ("🦷", ["tooth"]),
      ("🦴", ["bone"]),
      ("👀", ["eyes"]),
      ("👁️", ["eye"]),
      ("👅", ["tongue"]),
      ("👄", ["mouth"]),
      ("💋", ["kiss", "mark"]),
      ("💘", ["heart", "arrow"]),
      ("💝", ["heart", "ribbon"]),
      ("💖", ["sparkling", "heart"]),
      ("💗", ["growing", "heart"]),
      ("💓", ["beating", "heart"]),
      ("💞", ["revolving", "hearts"]),
      ("💕", ["two", "hearts"]),
      ("💟", ["heart", "decoration"]),
      ("❣️", ["heart", "exclamation"]),
      ("💔", ["broken", "heart"]),
      ("❤️", ["red", "heart"]),
      ("🧡", ["orange", "heart"]),
      ("💛", ["yellow", "heart"]),
      ("💚", ["green", "heart"]),
      ("💙", ["blue", "heart"]),
      ("💜", ["purple", "heart"]),
      ("🖤", ["black", "heart"]),
      ("🤍", ["white", "heart"]),
      ("🤎", ["brown", "heart"]),
      ("💯", ["hundred", "points"]),
      ("💢", ["anger", "symbol"]),
      ("💥", ["collision"]),
      ("💫", ["dizzy"]),
      ("💦", ["sweat", "droplets"]),
      ("💨", ["dashing", "away"]),
      ("🕳️", ["hole"]),
      ("💣", ["bomb"]),
      ("💬", ["speech", "balloon"]),
      ("👁️‍🗨️", ["eye", "speech", "bubble"]),
      ("🗨️", ["left", "speech", "bubble"]),
      ("🗯️", ["right", "anger", "bubble"]),
      ("💭", ["thought", "balloon"]),
      ("💤", ["zzz"]),
    ]
    
    var results: [(emoji: String, name: String)] = []
    
    for (emoji, keywords) in emojiDatabase {
      // Check if query matches any keyword
      let matches = keywords.contains { keyword in
        keyword.lowercased().hasPrefix(query) || keyword.lowercased().contains(query)
      }
      
      if matches {
        // Use first keyword as name
        let name = keywords.first?.capitalized ?? emoji
        results.append((emoji: emoji, name: name))
      }
    }
    
    // Limit results
    return Array(results.prefix(20))
  }
  
  /// Add emoji to recently used
  @MainActor
  public func addRecentlyUsed(_ shortcode: String) {
    recentlyUsed.removeAll { $0 == shortcode }
    recentlyUsed.insert(shortcode, at: 0)
    recentlyUsed = Array(recentlyUsed.prefix(maxRecentlyUsed))
  }
  
  /// Clear cache for account
  @MainActor
  public func clearCache(accountId: String) {
    emojiCache.removeValue(forKey: accountId)
  }
}
