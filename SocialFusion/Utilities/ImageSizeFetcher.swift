import Foundation
import UIKit
import ImageIO

/// Fetches image dimensions without downloading the full image
/// Uses HTTP Range requests to read just the image header
enum ImageSizeFetcher {
  /// Fetch image size asynchronously
  /// Returns nil if size cannot be determined
  static func fetchImageSize(url: URL) async -> CGSize? {
    // First check cache
    if let cached = await MediaDimensionCache.shared.getDimension(for: url.absoluteString) {
      return cached
    }
    
    // Try to get size from URL request (Range request for header)
    if let size = await fetchSizeViaRangeRequest(url: url) {
      // Cache the result
      await MediaDimensionCache.shared.setDimension(size, for: url.absoluteString)
      return size
    }
    
    // Fallback: download minimal data and parse
    if let size = await fetchSizeViaMinimalDownload(url: url) {
      await MediaDimensionCache.shared.setDimension(size, for: url.absoluteString)
      return size
    }
    
    return nil
  }
  
  /// Attempt to get size via HTTP Range request (just header)
  private static func fetchSizeViaRangeRequest(url: URL) async -> CGSize? {
    var request = URLRequest(url: url)
    request.setValue("bytes=0-32767", forHTTPHeaderField: "Range")  // First 32KB should contain header
    request.timeoutInterval = 5.0
    
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      
      // Check if we got a partial content response
      if let httpResponse = response as? HTTPURLResponse,
         httpResponse.statusCode == 206 || httpResponse.statusCode == 200 {
        return parseImageSize(from: data)
      }
    } catch {
      // Range request failed, try other methods
    }
    
    return nil
  }
  
  /// Fallback: download minimal data and parse
  private static func fetchSizeViaMinimalDownload(url: URL) async -> CGSize? {
    var request = URLRequest(url: url)
    request.setValue("bytes=0-32767", forHTTPHeaderField: "Range")
    request.timeoutInterval = 5.0
    
    do {
      let (data, _) = try await URLSession.shared.data(for: request)
      return parseImageSize(from: data)
    } catch {
      return nil
    }
  }
  
  /// Parse image size from data (supports JPEG, PNG, WebP, HEIF)
  private static func parseImageSize(from data: Data) -> CGSize? {
    // Try ImageIO first (supports JPEG, PNG, HEIF, WebP on iOS)
    if let source = CGImageSourceCreateWithData(data as CFData, nil),
       let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
      if let width = properties[kCGImagePropertyPixelWidth as String] as? CGFloat,
         let height = properties[kCGImagePropertyPixelHeight as String] as? CGFloat {
        return CGSize(width: width, height: height)
      }
    }
    
    // Fallback: manual parsing for common formats
    // JPEG: Look for SOF markers
    if data.count >= 2, data[0] == 0xFF, data[1] == 0xD8 {
      return parseJPEGSize(data: data)
    }
    
    // PNG: Fixed header structure
    if data.count >= 24,
       data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47 {
      return parsePNGSize(data: data)
    }
    
    return nil
  }
  
  /// Parse JPEG size from SOF markers
  private static func parseJPEGSize(data: Data) -> CGSize? {
    var i = 2  // Skip FF D8
    
    while i < data.count - 1 {
      if data[i] == 0xFF {
        let marker = data[i + 1]
        
        // SOF markers (Start of Frame)
        if marker >= 0xC0 && marker <= 0xC3 {
          if i + 7 < data.count {
            let height = (Int(data[i + 5]) << 8) | Int(data[i + 6])
            let width = (Int(data[i + 7]) << 8) | Int(data[i + 8])
            if width > 0 && height > 0 {
              return CGSize(width: CGFloat(width), height: CGFloat(height))
            }
          }
        }
        
        // Skip marker segment
        if i + 3 < data.count {
          let segmentLength = (Int(data[i + 2]) << 8) | Int(data[i + 3])
          i += 2 + segmentLength
        } else {
          break
        }
      } else {
        i += 1
      }
    }
    
    return nil
  }
  
  /// Parse PNG size from IHDR chunk
  private static func parsePNGSize(data: Data) -> CGSize? {
    // PNG structure: 8-byte signature, then IHDR chunk
    // IHDR is at offset 8, width is at offset 16 (4 bytes), height at offset 20 (4 bytes)
    if data.count >= 24 {
      let width = (Int(data[16]) << 24) | (Int(data[17]) << 16) | (Int(data[18]) << 8) | Int(data[19])
      let height = (Int(data[20]) << 24) | (Int(data[21]) << 16) | (Int(data[22]) << 8) | Int(data[23])
      
      if width > 0 && height > 0 {
        return CGSize(width: CGFloat(width), height: CGFloat(height))
      }
    }
    
    return nil
  }
}
