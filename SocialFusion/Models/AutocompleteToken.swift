import Foundation
import UIKit

/// Deterministic token state for autocomplete
/// Represents a single autocomplete token (@mention, #hashtag, :emoji) at a specific point in the document
public struct AutocompleteToken: Equatable {
  /// The trigger prefix ("@", "#", or ":")
  public let prefix: String
  
  /// The query substring after prefix up to caret
  public let query: String
  
  /// Range to replace when accepting suggestion (in UTF-16)
  public let replaceRange: NSRange
  
  /// Caret position for overlay anchoring (from UITextView)
  public var caretRect: CGRect
  
  /// Active destinations (for filtering and cache keys)
  /// Includes both platform and account ID for per-account scoping
  public let scope: [String] // DestinationID strings (platform:accountId format)
  
  /// Document revision when token was extracted
  public let documentRevision: Int
  
  /// Unique ID for this search request
  public let requestID: UUID
  
  public init(
    prefix: String,
    query: String,
    replaceRange: NSRange,
    caretRect: CGRect,
    scope: [String],
    documentRevision: Int,
    requestID: UUID
  ) {
    self.prefix = prefix
    self.query = query
    self.replaceRange = replaceRange
    self.caretRect = caretRect
    self.scope = scope
    self.documentRevision = documentRevision
    self.requestID = requestID
  }
}

/// Helper to create destination ID string from platform and account
public func makeDestinationID(platform: SocialPlatform, accountId: String) -> String {
  return "\(platform.rawValue):\(accountId)"
}
