import Foundation
import CoreGraphics

/// Canvas aspect ratio presets for share images
/// Optimized for various social media platforms and messaging apps
public enum ShareCanvasPreset: String, CaseIterable, Sendable {
    case ratio4x3   // Landscape, good for short posts
    case ratio1x1   // Square, universal
    case ratio4x5   // Portrait, Instagram-friendly
    case ratio9x16  // Tall portrait, Stories/Reels

    /// The aspect ratio as width / height
    public var aspectRatio: CGFloat {
        switch self {
        case .ratio4x3:  return 4.0 / 3.0   // 1.333...
        case .ratio1x1:  return 1.0         // 1.0
        case .ratio4x5:  return 4.0 / 5.0   // 0.8
        case .ratio9x16: return 9.0 / 16.0  // 0.5625
        }
    }

    /// Human-readable name for debugging/logging
    public var displayName: String {
        switch self {
        case .ratio4x3:  return "4:3"
        case .ratio1x1:  return "1:1"
        case .ratio4x5:  return "4:5"
        case .ratio9x16: return "9:16"
        }
    }

    /// Whether this is a portrait (tall) orientation
    public var isPortrait: Bool {
        aspectRatio < 1.0
    }

    /// Whether this is a landscape (wide) orientation
    public var isLandscape: Bool {
        aspectRatio > 1.0
    }

    /// Calculate canvas size from the short side dimension
    /// For portrait presets (4:5, 9:16), short side is width
    /// For landscape presets (4:3), short side is height
    /// For square (1:1), both sides are equal
    public func canvasSize(shortSide: CGFloat = 1080) -> CGSize {
        switch self {
        case .ratio4x3:
            // Landscape: short side is height
            let height = shortSide
            let width = round(height * aspectRatio)
            return CGSize(width: width, height: height)

        case .ratio1x1:
            // Square: both sides equal
            return CGSize(width: shortSide, height: shortSide)

        case .ratio4x5:
            // Portrait: short side is width
            let width = shortSide
            let height = round(width / aspectRatio)
            return CGSize(width: width, height: height)

        case .ratio9x16:
            // Portrait: short side is width
            let width = shortSide
            let height = round(width / aspectRatio)
            return CGSize(width: width, height: height)
        }
    }

    /// The short side of the canvas (minimum dimension)
    public func shortSide(for size: CGSize) -> CGFloat {
        min(size.width, size.height)
    }

    /// Ordered by preference for general use (most versatile first)
    public static var orderedByVersatility: [ShareCanvasPreset] {
        [.ratio4x3, .ratio1x1, .ratio4x5, .ratio9x16]
    }

    /// Ordered by height (shortest to tallest)
    public static var orderedByHeight: [ShareCanvasPreset] {
        [.ratio4x3, .ratio1x1, .ratio4x5, .ratio9x16]
    }
}
