import Foundation

/// Provider for timeline-aware suggestions
/// Converts TimelineContextSnapshot to AutocompleteSuggestion array
public final class TimelineContextSuggestionProvider: SuggestionProvider {
  
  public let priority: Int = 2 // Second priority (after local history)
  
  private let contextProvider: TimelineContextProvider
  private let scope: AutocompleteTimelineScope
  
  public init(contextProvider: TimelineContextProvider, scope: AutocompleteTimelineScope) {
    self.contextProvider = contextProvider
    self.scope = scope
  }
  
  public func canHandle(prefix: String) -> Bool {
    return prefix == "@" || prefix == "#"
  }
  
  public func suggestions(for token: AutocompleteToken) async -> [AutocompleteSuggestion] {
    guard canHandle(prefix: token.prefix) else {
      return []
    }
    
    let snapshot = contextProvider.snapshot(for: scope)
    let queryLower = token.query.lowercased()
    
    var suggestions: [AutocompleteSuggestion] = []
    
    switch token.prefix {
    case "@":
      // Convert AuthorContext to AutocompleteSuggestion
      for author in snapshot.recentAuthors {
        // Filter by query if provided
        if !queryLower.isEmpty {
          let usernameMatch = author.username.lowercased().contains(queryLower)
          let displayNameMatch = author.displayName?.lowercased().contains(queryLower) ?? false
          if !usernameMatch && !displayNameMatch {
            continue
          }
        }
        
        // Create suggestion from author context
        let payloadData: [String: Any]
        if author.canonicalID.platform == .bluesky {
          payloadData = [
            "did": author.canonicalID.stableID ?? "",
            "handle": author.username,
            "displayName": author.displayName ?? ""
          ]
        } else {
          payloadData = [
            "accountId": author.canonicalID.stableID ?? "",
            "acct": author.username,
            "displayName": author.displayName ?? ""
          ]
        }
        
        let suggestion = AutocompleteSuggestion(
          id: author.id,
          displayText: "@\(author.username)",
          subtitle: author.displayName,
          platforms: [author.canonicalID.platform],
          entityPayload: EntityPayload(platform: author.canonicalID.platform, data: payloadData),
          isRecent: false, // Timeline context is separate from recent cache
          isFollowed: author.isFollowed,
          avatarURL: author.avatarURL?.absoluteString
        )
        
        suggestions.append(suggestion)
      }
      
      // Also include conversation participants (for reply context)
      for participant in snapshot.conversationParticipants {
        // Avoid duplicates
        if suggestions.contains(where: { $0.id == participant.id }) {
          continue
        }
        
        // Filter by query if provided
        if !queryLower.isEmpty {
          let usernameMatch = participant.username.lowercased().contains(queryLower)
          let displayNameMatch = participant.displayName?.lowercased().contains(queryLower) ?? false
          if !usernameMatch && !displayNameMatch {
            continue
          }
        }
        
        let payloadData: [String: Any]
        if participant.canonicalID.platform == .bluesky {
          payloadData = [
            "did": participant.canonicalID.stableID ?? "",
            "handle": participant.username,
            "displayName": participant.displayName ?? ""
          ]
        } else {
          payloadData = [
            "accountId": participant.canonicalID.stableID ?? "",
            "acct": participant.username,
            "displayName": participant.displayName ?? ""
          ]
        }
        
        let suggestion = AutocompleteSuggestion(
          id: participant.id,
          displayText: "@\(participant.username)",
          subtitle: participant.displayName,
          platforms: [participant.canonicalID.platform],
          entityPayload: EntityPayload(platform: participant.canonicalID.platform, data: payloadData),
          isRecent: false,
          isFollowed: participant.isFollowed,
          avatarURL: participant.avatarURL?.absoluteString
        )
        
        suggestions.append(suggestion)
      }
      
      // Include mentions from timeline
      for mention in snapshot.recentMentions {
        // Filter by query if provided
        if !queryLower.isEmpty {
          let handleMatch = mention.handle.lowercased().contains(queryLower)
          if !handleMatch {
            continue
          }
        }
        
        // Avoid duplicates with authors
        if suggestions.contains(where: { $0.displayText.lowercased() == "@\(mention.handle.lowercased())" }) {
          continue
        }
        
        // Create suggestion from mention context
        // Note: We may not have full user info, so create minimal suggestion
        let platform: SocialPlatform = mention.canonicalID?.platform ?? .mastodon // Default to mastodon
        let payloadData: [String: Any] = [
          "handle": mention.handle,
          "displayName": ""
        ]
        
        let suggestion = AutocompleteSuggestion(
          id: mention.id,
          displayText: mention.handle.hasPrefix("@") ? mention.handle : "@\(mention.handle)",
          subtitle: nil,
          platforms: [platform],
          entityPayload: EntityPayload(platform: platform, data: payloadData),
          isRecent: false,
          isFollowed: false,
          avatarURL: nil
        )
        
        suggestions.append(suggestion)
      }
      
    case "#":
      // Convert HashtagContext to AutocompleteSuggestion
      for hashtag in snapshot.recentHashtags {
        // Filter by query if provided
        if !queryLower.isEmpty {
          let tagMatch = hashtag.tag.lowercased().contains(queryLower)
          if !tagMatch {
            continue
          }
        }
        
        let normalizedTag = hashtag.tag.lowercased()
        let cleanTag = normalizedTag.hasPrefix("#") ? String(normalizedTag.dropFirst()) : normalizedTag
        
        let suggestion = AutocompleteSuggestion(
          id: hashtag.id,
          displayText: "#\(hashtag.tag.hasPrefix("#") ? String(hashtag.tag.dropFirst()) : hashtag.tag)",
          subtitle: nil,
          platforms: [.mastodon], // Hashtags are primarily Mastodon
          entityPayload: EntityPayload(platform: .mastodon, data: ["tag": cleanTag]),
          isRecent: false,
          isFollowed: false,
          avatarURL: nil
        )
        
        suggestions.append(suggestion)
      }
      
    default:
      break
    }
    
    return suggestions
  }
}
