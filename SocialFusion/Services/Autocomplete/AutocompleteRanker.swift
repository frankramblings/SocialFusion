import Foundation

/// Ranks autocomplete suggestions using context-aware heuristics
/// Inspired by IceCubes, refined for cross-network use
public struct AutocompleteRanker {
  
  /// Score a suggestion based on context
  /// Higher score = higher priority
  public static func score(
    suggestion: AutocompleteSuggestion,
    context: TimelineContextSnapshot?
  ) -> Double {
    var score: Double = 0
    
    // Tier 1: Recency boost (from cache)
    if suggestion.isRecent {
      score += 1000
    }
    
    // Tier 2: Timeline context boost
    if let context = context {
      // Check if suggestion matches a recent author
      if let authorMatch = context.recentAuthors.first(where: { matches(suggestion: suggestion, author: $0) }) {
        // Recency weight (more recent = higher weight, max 100 points)
        let secondsSinceSeen = Date().timeIntervalSince(authorMatch.lastSeenAt)
        let recencyWeight = max(0, 100 - min(secondsSinceSeen / 60, 100)) // Decay over ~100 minutes
        
        // Appearance weight (more appearances = higher weight)
        let appearanceWeight = Double(authorMatch.appearanceCount) * 10
        
        // Follow boost
        let followBoost = authorMatch.isFollowed ? 50.0 : 0.0
        
        score += recencyWeight + appearanceWeight + followBoost
      }
      
      // Check if suggestion matches a conversation participant (for replies)
      if let participantMatch = context.conversationParticipants.first(where: { matches(suggestion: suggestion, author: $0) }) {
        // Conversation participants get extra boost
        score += 200
        if participantMatch.isFollowed {
          score += 50
        }
      }
      
      // Check if suggestion matches a recent mention
      if let mentionMatch = context.recentMentions.first(where: { matches(suggestion: suggestion, mention: $0) }) {
        let secondsSinceSeen = Date().timeIntervalSince(mentionMatch.lastSeenAt)
        let recencyWeight = max(0, 50 - min(secondsSinceSeen / 60, 50))
        let appearanceWeight = Double(mentionMatch.appearanceCount) * 5
        score += recencyWeight + appearanceWeight
      }
      
      // Check if suggestion matches a recent hashtag
      if let hashtagMatch = context.recentHashtags.first(where: { matches(suggestion: suggestion, hashtag: $0) }) {
        let secondsSinceSeen = Date().timeIntervalSince(hashtagMatch.lastSeenAt)
        let recencyWeight = max(0, 30 - min(secondsSinceSeen / 60, 30))
        let appearanceWeight = Double(hashtagMatch.appearanceCount) * 3
        score += recencyWeight + appearanceWeight
      }
    }
    
    // Tier 3: Follow boost (independent of timeline context)
    if suggestion.isFollowed {
      score += 500
    }
    
    // Tier 4: Base score (for network results without context)
    score += 100
    
    return score
  }
  
  /// Rank suggestions by score, maintaining stable ordering
  public static func rank(
    _ suggestions: [AutocompleteSuggestion],
    context: TimelineContextSnapshot?
  ) -> [AutocompleteSuggestion] {
    // Score each suggestion
    let scored = suggestions.map { suggestion in
      (suggestion: suggestion, score: score(suggestion: suggestion, context: context))
    }
    
    // Sort by score (descending), then by display text for stability
    let sorted = scored.sorted { lhs, rhs in
      if lhs.score != rhs.score {
        return lhs.score > rhs.score
      }
      // Stable sort by display text
      return lhs.suggestion.displayText < rhs.suggestion.displayText
    }
    
    return sorted.map { $0.suggestion }
  }
  
  // MARK: - Matching Helpers
  
  private static func matches(suggestion: AutocompleteSuggestion, author: AuthorContext) -> Bool {
    // Match by canonical ID if available
    if let stableID = author.canonicalID.stableID, !stableID.isEmpty {
      if suggestion.id == stableID {
        return true
      }
    }
    
    // Match by normalized handle
    let suggestionHandle = suggestion.displayText.lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "@", with: "")
    
    let authorHandle = author.username.lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "@", with: "")
    
    if suggestionHandle == authorHandle {
      return true
    }
    
    // Match by platform-specific ID
    if suggestion.id == author.id {
      return true
    }
    
    return false
  }
  
  private static func matches(suggestion: AutocompleteSuggestion, mention: MentionContext) -> Bool {
    let suggestionHandle = suggestion.displayText.lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "@", with: "")
    
    let mentionHandle = mention.handle.lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "@", with: "")
    
    return suggestionHandle == mentionHandle || suggestion.id == mention.id
  }
  
  private static func matches(suggestion: AutocompleteSuggestion, hashtag: HashtagContext) -> Bool {
    let suggestionTag = suggestion.displayText.lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "#", with: "")
    
    let hashtagTag = hashtag.tag.lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "#", with: "")
    
    return suggestionTag == hashtagTag || suggestion.id == hashtag.id
  }
}
