import Foundation

/// Utility for extracting autocomplete tokens (@mentions, #hashtags, :emoji) from text
/// Handles exact character constraints, stop conditions, and Unicode edge cases
public struct TokenExtractor {
  /// Extract an autocomplete token at the given caret location
  /// - Parameters:
  ///   - text: The full text string
  ///   - caretLocation: The caret position (UTF-16 offset)
  ///   - prefix: The trigger character ("@", "#", or ":")
  ///   - scope: Active destinations for filtering
  ///   - documentRevision: Current document revision
  ///   - caretRect: Caret rectangle for overlay positioning
  /// - Returns: AutocompleteToken if valid token found, nil otherwise
  public static func extractToken(
    text: String,
    caretLocation: Int,
    prefix: String,
    scope: [String] = [],
    documentRevision: Int = 0,
    caretRect: CGRect = .zero
  ) -> AutocompleteToken? {
    guard caretLocation > 0 && caretLocation <= text.utf16.count else {
      return nil
    }
    
    let nsString = text as NSString
    let beforeCaret = nsString.substring(to: caretLocation)
    
    // Find the trigger character before caret (using NSString for NSRange compatibility)
    let beforeCaretNS = beforeCaret as NSString
    let triggerLocation = beforeCaretNS.range(of: prefix, options: .backwards).location
    if triggerLocation == NSNotFound {
      return nil
    }
    
    let afterTrigger = nsString.substring(from: triggerLocation + prefix.utf16.count)
    
    // Determine allowed character set based on prefix
    let allowedChars: CharacterSet
    switch prefix {
    case "@":
      // Mentions: ASCII [A-Za-z0-9_\.] and -, allow single @ for user@domain
      allowedChars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-@")
    case "#":
      // Hashtags: Unicode letters, digits, underscore
      allowedChars = CharacterSet.letters.union(CharacterSet.decimalDigits).union(CharacterSet(charactersIn: "_"))
    case ":":
      // Emoji: letters, digits, underscore, hyphen
      allowedChars = CharacterSet.letters.union(CharacterSet.decimalDigits).union(CharacterSet(charactersIn: "_-"))
    default:
      return nil
    }
    
    // Stop characters: whitespace, punctuation (except underscore for hashtags/emoji), newline
    let stopChars: CharacterSet
    if prefix == "#" || prefix == ":" {
      stopChars = CharacterSet.whitespacesAndNewlines.union(CharacterSet.punctuationCharacters).subtracting(CharacterSet(charactersIn: "_"))
    } else {
      stopChars = CharacterSet.whitespacesAndNewlines.union(CharacterSet.punctuationCharacters).subtracting(CharacterSet(charactersIn: "_.-@"))
    }
    
    // Scan forward from trigger, collecting allowed chars until stop char or newline
    var query = ""
    var queryEndLocation = triggerLocation + prefix.utf16.count
    
    for char in afterTrigger {
      let charString = String(char)
      
      // Stop on newline (always breaks token)
      if charString.rangeOfCharacter(from: CharacterSet.newlines) != nil {
        break
      }
      
      // Stop on stop characters
      if charString.rangeOfCharacter(from: stopChars) != nil {
        break
      }
      
      // Only include allowed characters
      if charString.rangeOfCharacter(from: allowedChars) != nil {
        query += charString
        queryEndLocation += charString.utf16.count
      } else {
        break
      }
      
      // For mentions, allow single @ in interior for user@domain format
      if prefix == "@" && char == "@" && !query.contains("@") {
        query += charString
        queryEndLocation += charString.utf16.count
      } else if prefix == "@" && char == "@" {
        // Second @ stops the token
        break
      }
    }
    
    // Must have at least one character after trigger (or trigger itself for @)
    if query.isEmpty && prefix != "@" {
      return nil
    }
    
    // Build replace range (from trigger to current position)
    let replaceRange = NSRange(location: triggerLocation, length: queryEndLocation - triggerLocation)
    
    return AutocompleteToken(
      prefix: prefix,
      query: query,
      replaceRange: replaceRange,
      caretRect: caretRect,
      scope: scope,
      documentRevision: documentRevision,
      requestID: UUID()
    )
  }
}
