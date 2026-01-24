import Foundation
import CoreGraphics

/// Calculates safe zone insets for share image canvases
/// Ensures content isn't cropped when images are displayed in messaging apps
public struct SafeInsetCalculator {

    /// Safe insets for a canvas, accounting for platform-specific cropping
    public struct SafeInsets: Equatable, Sendable {
        /// Horizontal (left/right) safe inset in pixels
        public let x: CGFloat
        /// Vertical (top/bottom) safe inset in pixels
        public let y: CGFloat

        /// Total horizontal margin (left + right)
        public var totalHorizontal: CGFloat { x * 2 }

        /// Total vertical margin (top + bottom)
        public var totalVertical: CGFloat { y * 2 }
    }

    // MARK: - Configuration Constants

    /// Base inset as percentage of short side (8%)
    private static let baseInsetPercentage: CGFloat = 0.08

    /// Minimum inset in pixels (ensures visibility on small screens)
    private static let minimumInset: CGFloat = 64

    /// Horizontal bias multiplier (iMessage crops sides more aggressively)
    private static let horizontalBias: CGFloat = 1.15

    /// Vertical compression (less margin needed top/bottom)
    private static let verticalCompression: CGFloat = 0.90

    // MARK: - Public API

    /// Compute safe insets for a given canvas short side dimension
    /// - Parameter shortSide: The shorter dimension of the canvas in pixels
    /// - Returns: Safe insets for horizontal and vertical margins
    public static func computeSafeInsets(shortSide: CGFloat) -> SafeInsets {
        // Base inset: 8% of short side, minimum 64px
        let baseInset = max(round(shortSide * baseInsetPercentage), minimumInset)

        // Apply horizontal bias for iMessage side-crop protection
        let safeInsetX = round(baseInset * horizontalBias)

        // Apply vertical compression (less margin needed vertically)
        let safeInsetY = round(baseInset * verticalCompression)

        return SafeInsets(x: safeInsetX, y: safeInsetY)
    }

    /// Compute safe insets for a canvas preset
    /// - Parameters:
    ///   - preset: The canvas aspect ratio preset
    ///   - shortSide: The short side dimension (default 1080px)
    /// - Returns: Safe insets for the canvas
    public static func computeSafeInsets(
        for preset: ShareCanvasPreset,
        shortSide: CGFloat = 1080
    ) -> SafeInsets {
        let canvasSize = preset.canvasSize(shortSide: shortSide)
        let actualShortSide = min(canvasSize.width, canvasSize.height)
        return computeSafeInsets(shortSide: actualShortSide)
    }

    /// Calculate the available content area after applying safe insets
    /// - Parameters:
    ///   - preset: The canvas aspect ratio preset
    ///   - shortSide: The short side dimension (default 1080px)
    /// - Returns: Size of the content-safe area
    public static func contentArea(
        for preset: ShareCanvasPreset,
        shortSide: CGFloat = 1080
    ) -> CGSize {
        let canvasSize = preset.canvasSize(shortSide: shortSide)
        let insets = computeSafeInsets(for: preset, shortSide: shortSide)

        return CGSize(
            width: canvasSize.width - insets.totalHorizontal,
            height: canvasSize.height - insets.totalVertical
        )
    }

    /// Calculate the maximum card width for a preset (canvas width minus horizontal insets)
    /// - Parameters:
    ///   - preset: The canvas aspect ratio preset
    ///   - shortSide: The short side dimension (default 1080px)
    /// - Returns: Maximum card width in pixels
    public static func maxCardWidth(
        for preset: ShareCanvasPreset,
        shortSide: CGFloat = 1080
    ) -> CGFloat {
        let canvasSize = preset.canvasSize(shortSide: shortSide)
        let insets = computeSafeInsets(for: preset, shortSide: shortSide)
        return canvasSize.width - insets.totalHorizontal
    }

    /// Calculate the maximum card height for a preset (canvas height minus vertical insets)
    /// - Parameters:
    ///   - preset: The canvas aspect ratio preset
    ///   - shortSide: The short side dimension (default 1080px)
    /// - Returns: Maximum card height in pixels
    public static func maxCardHeight(
        for preset: ShareCanvasPreset,
        shortSide: CGFloat = 1080
    ) -> CGFloat {
        let canvasSize = preset.canvasSize(shortSide: shortSide)
        let insets = computeSafeInsets(for: preset, shortSide: shortSide)
        return canvasSize.height - insets.totalVertical
    }
}
