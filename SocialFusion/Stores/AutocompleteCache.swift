import Foundation

/// Per-account storage for autocomplete cache (recent mentions/hashtags)
@MainActor
public class AutocompleteCache {
  public static let shared = AutocompleteCache()
  
  private struct CachedResult {
    let suggestions: [AutocompleteSuggestion]
    let timestamp: Date
    let ttl: TimeInterval
  }
  
  /// Serializable representation of AutocompleteSuggestion for persistence
  private struct SerializableSuggestion: Codable {
    let id: String
    let displayText: String
    let subtitle: String?
    let platforms: [String] // SocialPlatform.rawValue
    let platform: String // Primary platform for EntityPayload
    let payloadData: [String: String] // Simplified payload data (all values as strings)
    let isRecent: Bool
    let isFollowed: Bool
    let avatarURL: String?
    
    init(from suggestion: AutocompleteSuggestion) {
      self.id = suggestion.id
      self.displayText = suggestion.displayText
      self.subtitle = suggestion.subtitle
      self.platforms = suggestion.platforms.map { $0.rawValue }
      self.platform = suggestion.entityPayload.platform.rawValue
      // Convert payload data to String values for Codable
      self.payloadData = suggestion.entityPayload.data.reduce(into: [String: String]()) { result, pair in
        result[pair.key] = String(describing: pair.value)
      }
      self.isRecent = suggestion.isRecent
      self.isFollowed = suggestion.isFollowed
      self.avatarURL = suggestion.avatarURL
    }
    
    func toAutocompleteSuggestion() -> AutocompleteSuggestion? {
      guard let primaryPlatform = SocialPlatform(rawValue: platform) else {
        return nil
      }
      
      let platformsSet = Set(platforms.compactMap { SocialPlatform(rawValue: $0) })
      
      // Reconstruct payload data (convert strings back to appropriate types)
      var reconstructedData: [String: Any] = [:]
      for (key, stringValue) in payloadData {
        // Try to preserve original types where possible
        // For now, store as strings - they'll be converted when needed
        reconstructedData[key] = stringValue
      }
      
      let entityPayload = EntityPayload(platform: primaryPlatform, data: reconstructedData)
      
      return AutocompleteSuggestion(
        id: id,
        displayText: displayText,
        subtitle: subtitle,
        platforms: platformsSet,
        entityPayload: entityPayload,
        isRecent: isRecent,
        isFollowed: isFollowed,
        avatarURL: avatarURL
      )
    }
  }
  
  private var cache: [String: CachedResult] = [:]
  private var recentMentions: [String: [AutocompleteSuggestion]] = [:] // Key: accountId
  private var recentHashtags: [String: [AutocompleteSuggestion]] = [:] // Key: accountId
  private var frequentlyUsed: [String: [AutocompleteSuggestion]] = [:] // Key: accountId
  private var usageCounts: [String: [String: Int]] = [:] // Key: accountId, value: [suggestionId: count]
  private let maxRecentItems = 50
  private let maxFrequentlyUsed = 20
  
  private let userDefaults = UserDefaults.standard
  private let mentionsKeyPrefix = "AutocompleteCache.recentMentions."
  private let hashtagsKeyPrefix = "AutocompleteCache.recentHashtags."
  private let frequentlyUsedKeyPrefix = "AutocompleteCache.frequentlyUsed."
  private let usageCountsKeyPrefix = "AutocompleteCache.usageCounts."
  
  private init() {
    loadFromUserDefaults()
  }
  
  /// Load cached data from UserDefaults
  private func loadFromUserDefaults() {
    // Load recent mentions
    for key in userDefaults.dictionaryRepresentation().keys {
      if key.hasPrefix(mentionsKeyPrefix) {
        let accountId = String(key.dropFirst(mentionsKeyPrefix.count))
        if let data = userDefaults.data(forKey: key) {
          if let serialized = try? JSONDecoder().decode([SerializableSuggestion].self, from: data) {
            let suggestions = serialized.compactMap { $0.toAutocompleteSuggestion() }
            if !suggestions.isEmpty {
              recentMentions[accountId] = suggestions
            }
          }
        }
      } else if key.hasPrefix(hashtagsKeyPrefix) {
        let accountId = String(key.dropFirst(hashtagsKeyPrefix.count))
        if let data = userDefaults.data(forKey: key) {
          if let serialized = try? JSONDecoder().decode([SerializableSuggestion].self, from: data) {
            let suggestions = serialized.compactMap { $0.toAutocompleteSuggestion() }
            if !suggestions.isEmpty {
              recentHashtags[accountId] = suggestions
            }
          }
        }
      } else if key.hasPrefix(frequentlyUsedKeyPrefix) {
        let accountId = String(key.dropFirst(frequentlyUsedKeyPrefix.count))
        if let data = userDefaults.data(forKey: key) {
          if let serialized = try? JSONDecoder().decode([SerializableSuggestion].self, from: data) {
            let suggestions = serialized.compactMap { $0.toAutocompleteSuggestion() }
            if !suggestions.isEmpty {
              frequentlyUsed[accountId] = suggestions
            }
          }
        }
      } else if key.hasPrefix(usageCountsKeyPrefix) {
        let accountId = String(key.dropFirst(usageCountsKeyPrefix.count))
        if let data = userDefaults.data(forKey: key),
           let counts = try? JSONDecoder().decode([String: Int].self, from: data) {
          usageCounts[accountId] = counts
        }
      }
    }
  }
  
  /// Save to UserDefaults
  private func saveToUserDefaults(accountId: String, mentions: [AutocompleteSuggestion]?, hashtags: [AutocompleteSuggestion]?) {
    if let mentions = mentions {
      let serialized = mentions.map { SerializableSuggestion(from: $0) }
      if let data = try? JSONEncoder().encode(serialized) {
        userDefaults.set(data, forKey: "\(mentionsKeyPrefix)\(accountId)")
      }
    }
    if let hashtags = hashtags {
      let serialized = hashtags.map { SerializableSuggestion(from: $0) }
      if let data = try? JSONEncoder().encode(serialized) {
        userDefaults.set(data, forKey: "\(hashtagsKeyPrefix)\(accountId)")
      }
    }
  }
  
  /// Save frequently used to UserDefaults
  private func saveFrequentlyUsedToUserDefaults(accountId: String) {
    if let frequentlyUsedList = frequentlyUsed[accountId] {
      let serialized = frequentlyUsedList.map { SerializableSuggestion(from: $0) }
      if let data = try? JSONEncoder().encode(serialized) {
        userDefaults.set(data, forKey: "\(frequentlyUsedKeyPrefix)\(accountId)")
      }
    }
    
    if let counts = usageCounts[accountId] {
      if let data = try? JSONEncoder().encode(counts) {
        userDefaults.set(data, forKey: "\(usageCountsKeyPrefix)\(accountId)")
      }
    }
  }
  
  /// Get cached suggestions
  public func get(key: String) -> [AutocompleteSuggestion]? {
    guard let cached = cache[key] else {
      return nil
    }
    
    // Check TTL
    if Date().timeIntervalSince(cached.timestamp) > cached.ttl {
      cache.removeValue(forKey: key)
      return nil
    }
    
    return cached.suggestions
  }
  
  /// Set cached suggestions
  public func set(key: String, value: [AutocompleteSuggestion], ttl: TimeInterval = 30) {
    cache[key] = CachedResult(suggestions: value, timestamp: Date(), ttl: ttl)
  }
  
  /// Add to recent mentions
  public func addRecentMention(_ suggestion: AutocompleteSuggestion, accountId: String) {
    if recentMentions[accountId] == nil {
      recentMentions[accountId] = []
    }
    
    var mentions = recentMentions[accountId] ?? []
    // Remove if already exists
    mentions.removeAll { $0.id == suggestion.id }
    // Add to front
    mentions.insert(suggestion, at: 0)
    // Limit to maxRecentItems
    mentions = Array(mentions.prefix(maxRecentItems))
    recentMentions[accountId] = mentions
    
    // Update usage count for frequently used
    incrementUsageCount(suggestionId: suggestion.id, accountId: accountId)
    
    // Persist to UserDefaults
    saveToUserDefaults(accountId: accountId, mentions: mentions, hashtags: nil)
  }
  
  /// Get recent mentions matching query prefix
  public func getRecentMentions(accountId: String, queryPrefix: String) -> [AutocompleteSuggestion] {
    guard let mentions = recentMentions[accountId] else {
      return []
    }
    
    let prefix = queryPrefix.lowercased()
    return mentions.filter { mention in
      mention.displayText.lowercased().hasPrefix("@\(prefix)") || 
      mention.displayText.lowercased().contains(prefix)
    }
  }
  
  /// Add to recent hashtags
  public func addRecentHashtag(_ suggestion: AutocompleteSuggestion, accountId: String) {
    if recentHashtags[accountId] == nil {
      recentHashtags[accountId] = []
    }
    
    var hashtags = recentHashtags[accountId] ?? []
    // Remove if already exists
    hashtags.removeAll { $0.id == suggestion.id }
    // Add to front
    hashtags.insert(suggestion, at: 0)
    // Limit to maxRecentItems
    hashtags = Array(hashtags.prefix(maxRecentItems))
    recentHashtags[accountId] = hashtags
    
    // Update usage count for frequently used
    incrementUsageCount(suggestionId: suggestion.id, accountId: accountId)
    
    // Persist to UserDefaults
    saveToUserDefaults(accountId: accountId, mentions: nil, hashtags: hashtags)
  }
  
  /// Increment usage count for a suggestion (for frequently used tracking)
  private func incrementUsageCount(suggestionId: String, accountId: String) {
    if usageCounts[accountId] == nil {
      usageCounts[accountId] = [:]
    }
    
    let currentCount = usageCounts[accountId]?[suggestionId] ?? 0
    usageCounts[accountId]?[suggestionId] = currentCount + 1
    
    // Update frequently used list
    updateFrequentlyUsed(accountId: accountId)
  }
  
  /// Update frequently used list based on usage counts
  private func updateFrequentlyUsed(accountId: String) {
    guard let counts = usageCounts[accountId] else { return }
    
    // Get all suggestions from recent mentions and hashtags
    var allSuggestions: [AutocompleteSuggestion] = []
    if let mentions = recentMentions[accountId] {
      allSuggestions.append(contentsOf: mentions)
    }
    if let hashtags = recentHashtags[accountId] {
      allSuggestions.append(contentsOf: hashtags)
    }
    
    // Sort by usage count (descending), then by recency
    let sorted = allSuggestions.sorted { suggestion1, suggestion2 in
      let count1 = counts[suggestion1.id] ?? 0
      let count2 = counts[suggestion2.id] ?? 0
      if count1 != count2 {
        return count1 > count2
      }
      // If counts are equal, prefer more recent (mentions/hashtags are already sorted by recency)
      return false
    }
    
    // Take top maxFrequentlyUsed
    frequentlyUsed[accountId] = Array(sorted.prefix(maxFrequentlyUsed))
    
    // Persist frequently used
    saveFrequentlyUsedToUserDefaults(accountId: accountId)
  }
  
  /// Get frequently used suggestions matching query prefix
  public func getFrequentlyUsed(accountId: String, queryPrefix: String) -> [AutocompleteSuggestion] {
    guard let frequentlyUsedList = frequentlyUsed[accountId] else {
      return []
    }
    
    let prefix = queryPrefix.lowercased()
    return frequentlyUsedList.filter { suggestion in
      suggestion.displayText.lowercased().hasPrefix(prefix) ||
      suggestion.displayText.lowercased().contains(prefix) ||
      (suggestion.subtitle?.lowercased().contains(prefix) ?? false)
    }
  }
  
  /// Get recent hashtags matching query prefix
  public func getRecentHashtags(accountId: String, queryPrefix: String) -> [AutocompleteSuggestion] {
    guard let hashtags = recentHashtags[accountId] else {
      return []
    }
    
    let prefix = queryPrefix.lowercased()
    return hashtags.filter { hashtag in
      hashtag.displayText.lowercased().hasPrefix("#\(prefix)") ||
      hashtag.displayText.lowercased().contains(prefix)
    }
  }
  
  /// Clear cache for account
  public func clear(accountId: String) {
    recentMentions.removeValue(forKey: accountId)
    recentHashtags.removeValue(forKey: accountId)
    frequentlyUsed.removeValue(forKey: accountId)
    usageCounts.removeValue(forKey: accountId)
    
    // Clear UserDefaults
    userDefaults.removeObject(forKey: "\(mentionsKeyPrefix)\(accountId)")
    userDefaults.removeObject(forKey: "\(hashtagsKeyPrefix)\(accountId)")
    userDefaults.removeObject(forKey: "\(frequentlyUsedKeyPrefix)\(accountId)")
    userDefaults.removeObject(forKey: "\(usageCountsKeyPrefix)\(accountId)")
    
    // Clear cache entries for this account
    cache = cache.filter { !$0.key.contains(accountId) }
  }
  
  /// Clear all cache
  public func clearAll() {
    cache.removeAll()
    recentMentions.removeAll()
    recentHashtags.removeAll()
    frequentlyUsed.removeAll()
    usageCounts.removeAll()
    
    // Clear all UserDefaults keys
    let keysToRemove = userDefaults.dictionaryRepresentation().keys.filter { key in
      key.hasPrefix(mentionsKeyPrefix) ||
      key.hasPrefix(hashtagsKeyPrefix) ||
      key.hasPrefix(frequentlyUsedKeyPrefix) ||
      key.hasPrefix(usageCountsKeyPrefix)
    }
    for key in keysToRemove {
      userDefaults.removeObject(forKey: key)
    }
  }
}
