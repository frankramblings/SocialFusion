import Foundation

/// Rich text model with plain text + entity metadata
/// Enables proper entity insertion for Bluesky (DID-based mentions) while maintaining readable text for Mastodon
public struct ComposerTextModel {
  /// Plain text content (single source of truth)
  public var text: String
  
  /// Array of entities with ranges
  public var entities: [TextEntity]
  
  /// Increments on each edit (for stale result rejection)
  public var documentRevision: Int
  
  public init(text: String = "", entities: [TextEntity] = [], documentRevision: Int = 0) {
    self.text = text
    self.entities = entities
    self.documentRevision = documentRevision
  }
  
  /// Apply an edit to the text and update all entity ranges
  /// - Parameters:
  ///   - replacementRange: Range to replace (in pre-edit coordinate space, UTF-16)
  ///   - replacementText: Text to insert
  /// - Returns: Delta (positive = insertion, negative = deletion)
  @discardableResult
  public mutating func applyEdit(replacementRange: NSRange, replacementText: String) -> Int {
    // Delta computation
    let delta = replacementText.utf16.count - replacementRange.length
    
    // Update text
    let nsString = text as NSString
    text = nsString.replacingCharacters(in: replacementRange, with: replacementText)
    
    // Update entity ranges
    var updatedEntities: [TextEntity] = []
    for var entity in entities {
      // Check if edit intersects entity range OR touches its interior
      let intersection = NSIntersectionRange(replacementRange, entity.range)
      if intersection.length > 0 {
        // Drop entity if edit intersects or touches interior
        continue
      }
      
      // Deletion at entity start (deleting trigger @/#/:)
      if replacementRange.location == entity.range.location && replacementRange.length > 0 {
        // Drop entity
        continue
      }
      
      // If edit is exactly at end boundary and is insertion (typing after entity)
      if replacementRange.location == entity.range.location + entity.range.length && delta > 0 {
        // Preserve entity, no range shift needed (insertion is after entity)
        // Entity range stays the same
      } else if replacementRange.location + replacementRange.length <= entity.range.location {
        // If edit is before entity: shift range by delta
        entity.range = NSRange(location: entity.range.location + delta, length: entity.range.length)
      } else if replacementRange.location >= entity.range.location + entity.range.length {
        // If edit is after entity: no change needed
        // Entity range stays the same
      }
      
      updatedEntities.append(entity)
    }
    
    entities = updatedEntities
    documentRevision += 1
    
    return delta
  }
  
  /// Atomic replace operation (used when accepting autocomplete suggestion)
  /// - Parameters:
  ///   - range: Range to replace
  ///   - replacementText: Text to insert
  ///   - newEntities: Entities to attach
  /// - Note: This creates a single atomic operation. Undo/redo integration
  ///   should register both text and entity changes in the same undo group.
  public mutating func replace(range: NSRange, with replacementText: String, entities newEntities: [TextEntity]) {
    // Validate range
    guard range.location >= 0 && range.location + range.length <= text.utf16.count else {
      // Invalid range - skip
      return
    }
    
    // Apply text replacement
    let nsString = text as NSString
    text = nsString.replacingCharacters(in: range, with: replacementText)
    
    // Calculate delta
    let delta = replacementText.utf16.count - range.length
    
    // Update existing entities that come after the replacement
    var updatedEntities: [TextEntity] = []
    for var entity in entities {
      // Remove entities that overlap with replacement range
      let intersection = NSIntersectionRange(range, entity.range)
      if intersection.length > 0 {
        continue
      }
      
      // Shift entities after the replacement
      if entity.range.location >= range.location + range.length {
        entity.range = NSRange(location: entity.range.location + delta, length: entity.range.length)
      }
      
      updatedEntities.append(entity)
    }
    
    // Add new entities, adjusting their ranges to account for replacement
    for var entity in newEntities {
      // New entity starts at replacement location
      entity.range = NSRange(location: range.location, length: replacementText.utf16.count)
      updatedEntities.append(entity)
    }
    
    entities = updatedEntities
    documentRevision += 1
  }
  
  /// Returns plain text (entities are metadata)
  public func toPlainText() -> String {
    return text
  }
  
  /// Compiles facets/mentions for Mastodon API
  /// Filters entities to Mastodon-compatible payloads
  public func toMastodonEntities() -> [MastodonEntity] {
    return entities.compactMap { entity -> MastodonEntity? in
      guard let mastodonPayload = entity.payloadByDestination.values.first(where: { $0.platform == .mastodon }) else {
        return nil
      }
      
      // Map range to byte offsets if required by API (using OffsetMapper)
      let byteRange = OffsetMapper.nsRangeToUTF8ByteRange(text: text, nsRange: entity.range) ?? entity.range
      
      return MastodonEntity(
        type: entity.kind.mastodonType,
        range: byteRange,
        payload: mastodonPayload
      )
    }
  }
  
  /// Compiles facets for Bluesky API
  /// Filters entities to Bluesky-compatible payloads (DID-based mentions)
  public func toBlueskyEntities() -> [BlueskyFacet] {
    return entities.compactMap { entity -> BlueskyFacet? in
      guard let blueskyPayload = entity.payloadByDestination.values.first(where: { $0.platform == .bluesky }) else {
        return nil
      }
      
      // Map range to offset unit required by Bluesky client (UTF-8 bytes or UTF-16, using OffsetMapper)
      // Bluesky facets typically use UTF-8 byte offsets
      let byteRange = OffsetMapper.nsRangeToUTF8ByteRange(text: text, nsRange: entity.range) ?? entity.range
      
      return BlueskyFacet(
        index: BlueskyFacetIndex(byteStart: byteRange.location, byteEnd: byteRange.location + byteRange.length),
        features: [blueskyPayload.toBlueskyFeature()]
      )
    }
  }
  
  /// Parse text for mentions, hashtags, and links and create entities
  /// This is called before posting to ensure manually typed entities are included
  /// - Parameter activeDestinations: Array of destination IDs (platform:accountId) for payload creation
  /// - Note: This only creates entities for text that doesn't already have entities
  public mutating func parseEntitiesFromText(activeDestinations: [String]) {
    let nsString = text as NSString
    let textLength = nsString.length
    var newEntities: [TextEntity] = []
    
    // Track ranges already covered by existing entities
    var coveredRanges: [NSRange] = entities.map { $0.range }
    
    // Parse mentions: @username or @username@domain
    let mentionPattern = "@([A-Za-z0-9_]+)(@[A-Za-z0-9_.-]+)?"
    if let mentionRegex = try? NSRegularExpression(pattern: mentionPattern, options: []) {
      let matches = mentionRegex.matches(in: text, options: [], range: NSRange(location: 0, length: textLength))
      for match in matches {
        let range = match.range
        // Skip if this range overlaps with an existing entity
        if coveredRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
          continue
        }
        
        let usernameRange = match.range(at: 1)
        let username = nsString.substring(with: usernameRange)
        var domain: String? = nil
        if match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound {
          let domainRange = match.range(at: 2)
          domain = nsString.substring(with: domainRange)
        }
        
        let displayText = nsString.substring(with: range)
        let acct = domain != nil ? "\(username)\(domain!)" : username
        
        // Create payloads for active destinations
        var payloads: [String: EntityPayload] = [:]
        for destinationID in activeDestinations {
          // Extract platform from destination ID (format: "platform:accountId")
          let components = destinationID.split(separator: ":")
          guard components.count >= 2,
                let platformStr = components.first,
                let platform = SocialPlatform(rawValue: String(platformStr)) else {
            continue
          }
          
          switch platform {
          case .mastodon:
            payloads[destinationID] = EntityPayload(
              platform: .mastodon,
              data: [
                "acct": acct,
                "username": username
              ]
            )
          case .bluesky:
            // For Bluesky, we'd need DID lookup - for now, store handle
            // In production, this should resolve DID via search
            payloads[destinationID] = EntityPayload(
              platform: .bluesky,
              data: [
                "handle": username,
                "did": "" // Would need to resolve via search
              ]
            )
          }
        }
        
        let entity = TextEntity(
          kind: .mention,
          range: range,
          displayText: displayText,
          payloadByDestination: payloads,
          data: .mention(MentionData(
            acct: acct,
            handle: username
          ))
        )
        newEntities.append(entity)
        coveredRanges.append(range)
      }
    }
    
    // Parse hashtags: #tag
    let hashtagPattern = "#([\\w]+)"
    if let hashtagRegex = try? NSRegularExpression(pattern: hashtagPattern, options: []) {
      let matches = hashtagRegex.matches(in: text, options: [], range: NSRange(location: 0, length: textLength))
      for match in matches {
        let range = match.range
        // Skip if this range overlaps with an existing entity
        if coveredRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
          continue
        }
        
        let tagRange = match.range(at: 1)
        let tag = nsString.substring(with: tagRange)
        let normalizedTag = tag.lowercased()
        let displayText = nsString.substring(with: range)
        
        // Create payloads for active destinations
        var payloads: [String: EntityPayload] = [:]
        for destinationID in activeDestinations {
          let components = destinationID.split(separator: ":")
          guard components.count >= 2,
                let platformStr = components.first,
                let platform = SocialPlatform(rawValue: String(platformStr)) else {
            continue
          }
          
          switch platform {
          case .mastodon:
            payloads[destinationID] = EntityPayload(
              platform: .mastodon,
              data: ["tag": normalizedTag]
            )
          case .bluesky:
            payloads[destinationID] = EntityPayload(
              platform: .bluesky,
              data: ["tag": normalizedTag]
            )
          }
        }
        
        let entity = TextEntity(
          kind: .hashtag,
          range: range,
          displayText: displayText,
          payloadByDestination: payloads,
          data: .hashtag(HashtagData(normalizedTag: normalizedTag))
        )
        newEntities.append(entity)
        coveredRanges.append(range)
      }
    }
    
    // Parse links: http:// or https:// URLs
    let urlPattern = "https?://[A-Za-z0-9./?=_%-]+"
    if let urlRegex = try? NSRegularExpression(pattern: urlPattern, options: []) {
      let matches = urlRegex.matches(in: text, options: [], range: NSRange(location: 0, length: textLength))
      for match in matches {
        var range = match.range
        // Clean trailing punctuation
        var urlText = nsString.substring(with: range)
        while let last = urlText.last, ".,!?;:".contains(last) {
          urlText = String(urlText.dropLast())
          range = NSRange(location: range.location, length: range.length - 1)
        }
        
        // Skip if this range overlaps with an existing entity
        if coveredRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
          continue
        }
        
        guard let url = URL(string: urlText) else { continue }
        
        // Create payloads for active destinations
        var payloads: [String: EntityPayload] = [:]
        for destinationID in activeDestinations {
          let components = destinationID.split(separator: ":")
          guard components.count >= 2,
                let platformStr = components.first,
                let platform = SocialPlatform(rawValue: String(platformStr)) else {
            continue
          }
          
          switch platform {
          case .mastodon:
            payloads[destinationID] = EntityPayload(
              platform: .mastodon,
              data: ["url": urlText]
            )
          case .bluesky:
            payloads[destinationID] = EntityPayload(
              platform: .bluesky,
              data: ["uri": urlText]
            )
          }
        }
        
        let entity = TextEntity(
          kind: .link,
          range: range,
          displayText: urlText,
          payloadByDestination: payloads,
          data: .link(LinkData(url: urlText))
        )
        newEntities.append(entity)
        coveredRanges.append(range)
      }
    }
    
    // Merge new entities with existing ones (existing entities take precedence)
    // Sort by location to maintain order
    var allEntities = entities + newEntities
    allEntities.sort { $0.range.location < $1.range.location }
    entities = allEntities
  }
}

/// Entity kind enumeration
public enum EntityKind: String, Codable {
  case mention
  case hashtag
  case link
  case emoji
  
  var mastodonType: String {
    switch self {
    case .mention: return "mention"
    case .hashtag: return "hashtag"
    case .link: return "link"
    case .emoji: return "emoji"
    }
  }
}

/// Concrete struct for text entities
public struct TextEntity: Identifiable, Equatable {
  /// Unique identifier
  public let id: UUID
  
  /// Entity kind
  public let kind: EntityKind
  
  /// UTF-16 range in text (CRITICAL: use NSRange, not String.Index)
  public var range: NSRange
  
  /// What user sees (e.g., "@handle" or "#tag")
  public let displayText: String
  
  /// Platform-specific payloads
  public var payloadByDestination: [String: EntityPayload]
  
  /// Associated data for the entity type
  public let data: EntityData
  
  public init(
    id: UUID = UUID(),
    kind: EntityKind,
    range: NSRange,
    displayText: String,
    payloadByDestination: [String: EntityPayload] = [:],
    data: EntityData
  ) {
    self.id = id
    self.kind = kind
    self.range = range
    self.displayText = displayText
    self.payloadByDestination = payloadByDestination
    self.data = data
  }
}

/// Enum containing type-specific data
public enum EntityData: Equatable {
  case mention(MentionData)
  case hashtag(HashtagData)
  case emoji(EmojiData)
  case link(LinkData)
}

/// Mention-specific data
public struct MentionData: Equatable {
  public var accountId: String? // Mastodon
  public var acct: String? // Mastodon (user@domain)
  public var displayName: String?
  public var did: String? // Bluesky
  public var handle: String? // Bluesky
  
  public init(
    accountId: String? = nil,
    acct: String? = nil,
    displayName: String? = nil,
    did: String? = nil,
    handle: String? = nil
  ) {
    self.accountId = accountId
    self.acct = acct
    self.displayName = displayName
    self.did = did
    self.handle = handle
  }
}

/// Hashtag-specific data
public struct HashtagData: Equatable {
  public let normalizedTag: String // Lowercase, normalized
  
  public init(normalizedTag: String) {
    self.normalizedTag = normalizedTag.lowercased()
  }
}

/// Emoji-specific data
public struct EmojiData: Equatable {
  public let shortcode: String // e.g., ":neofox_floof:"
  public let emojiURL: String? // Custom emoji image URL (Mastodon)
  public let unicodeEmoji: String? // Actual emoji character (system)
  
  public init(shortcode: String, emojiURL: String? = nil, unicodeEmoji: String? = nil) {
    self.shortcode = shortcode
    self.emojiURL = emojiURL
    self.unicodeEmoji = unicodeEmoji
  }
}

/// Link-specific data
public struct LinkData: Equatable {
  public let url: String
  public let title: String?
  
  public init(url: String, title: String? = nil) {
    self.url = url
    self.title = title
  }
}

/// Platform-specific entity payload
public struct EntityPayload {
  public let platform: SocialPlatform
  public let data: [String: Any]
  
  public init(platform: SocialPlatform, data: [String: Any]) {
    self.platform = platform
    self.data = data
  }
  
  func toBlueskyFeature() -> BlueskyFacetFeature {
    // Convert payload to Bluesky facet feature
    // This is a placeholder - actual implementation depends on Bluesky API structure
    return BlueskyFacetFeature.mention(did: data["did"] as? String ?? "")
  }
}

extension EntityPayload: Equatable {
  public static func == (lhs: EntityPayload, rhs: EntityPayload) -> Bool {
    guard lhs.platform == rhs.platform else { return false }
    // Compare data dictionaries using NSDictionary comparison
    let lhsDict = NSDictionary(dictionary: lhs.data)
    let rhsDict = NSDictionary(dictionary: rhs.data)
    return lhsDict.isEqual(rhsDict)
  }
}

/// Mastodon entity structure
public struct MastodonEntity {
  public let type: String
  public let range: NSRange
  public let payload: EntityPayload
}

/// Bluesky facet structure
public struct BlueskyFacet {
  public let index: BlueskyFacetIndex
  public let features: [BlueskyFacetFeature]
}

/// Bluesky facet index (byte offsets)
public struct BlueskyFacetIndex: Equatable {
  public let byteStart: Int
  public let byteEnd: Int
}

/// Bluesky facet feature
public enum BlueskyFacetFeature: Equatable {
  case mention(did: String)
  case link(uri: String)
  case hashtag(tag: String)
}
