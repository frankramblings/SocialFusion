import Foundation

/// Utility for converting NSRange (UTF-16) to different offset units required by platform APIs
/// Isolated conversion logic allows swapping implementations based on client requirements
public enum OffsetMapper {
  /// Convert NSRange (UTF-16 code units) to UTF-8 byte range
  /// - Parameters:
  ///   - text: The source text string
  ///   - nsRange: The UTF-16 range to convert
  /// - Returns: NSRange representing UTF-8 byte offsets, or nil if conversion fails
  public static func nsRangeToUTF8ByteRange(text: String, nsRange: NSRange) -> NSRange? {
    _ = Range(nsRange, in: text)
    
    // More reliable conversion using NSString
    let nsString = text as NSString
    let utf8StartBytes = nsString.substring(to: nsRange.location).utf8.count
    let utf8LengthBytes = nsString.substring(with: nsRange).utf8.count
    
    return NSRange(location: utf8StartBytes, length: utf8LengthBytes)
  }
  
  /// Convert NSRange to UTF-16 code unit range (identity function for NSRange)
  /// - Parameters:
  ///   - text: The source text string (unused, kept for API consistency)
  ///   - nsRange: The UTF-16 range (already in correct format)
  /// - Returns: The same NSRange (UTF-16 is what NSRange uses)
  public static func nsRangeToUTF16CodeUnitRange(text: String, nsRange: NSRange) -> NSRange {
    return nsRange
  }
}
