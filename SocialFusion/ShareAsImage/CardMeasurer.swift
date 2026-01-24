import SwiftUI
import UIKit

/// Measures the rendered height of share image cards at various widths
@MainActor
public struct CardMeasurer {

    /// Result of measuring a card at a specific width
    public struct Measurement: Sendable {
        /// The preset used for this measurement
        public let preset: ShareCanvasPreset
        /// The width the card was rendered at (in pixels)
        public let cardWidth: CGFloat
        /// The measured height of the card (in pixels)
        public let cardHeight: CGFloat
        /// Whether the card fits within the preset's safe area
        public let fitsInCanvas: Bool
    }

    // MARK: - Configuration

    /// Design width for the card in points (matches ShareImageRootView)
    private static let designWidth: CGFloat = 390

    /// Short side dimension for canvas calculations
    private static let shortSide: CGFloat = 1080

    // MARK: - Public API

    /// Measure the card height for a document at a specific preset's card width
    /// - Parameters:
    ///   - document: The share image document to measure
    ///   - preset: The canvas preset to measure for
    /// - Returns: Measurement result with card dimensions and fit status
    public static func measure(
        document: ShareImageDocument,
        for preset: ShareCanvasPreset
    ) -> Measurement {
        let cardWidth = SafeInsetCalculator.maxCardWidth(for: preset, shortSide: shortSide)
        let maxCardHeight = SafeInsetCalculator.maxCardHeight(for: preset, shortSide: shortSide)

        // Calculate scale from design width to target pixel width
        let scale = cardWidth / designWidth

        // Create the view at the target width
        let view = ShareImageRootView(
            document: document,
            targetPixelWidth: cardWidth
        )

        // Use ImageRenderer to measure the actual rendered size
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0  // We want pixel dimensions

        // Get the rendered image to measure its size
        let measuredHeight: CGFloat
        if let image = renderer.uiImage {
            measuredHeight = image.size.height
        } else {
            // Fallback: estimate height based on content
            measuredHeight = estimateHeight(for: document, scale: scale)
        }

        let fitsInCanvas = measuredHeight <= maxCardHeight

        return Measurement(
            preset: preset,
            cardWidth: cardWidth,
            cardHeight: measuredHeight,
            fitsInCanvas: fitsInCanvas
        )
    }

    /// Measure the card height for a document across all presets
    /// - Parameter document: The share image document to measure
    /// - Returns: Array of measurements for each preset
    public static func measureAll(
        document: ShareImageDocument
    ) -> [Measurement] {
        ShareCanvasPreset.allCases.map { preset in
            measure(document: document, for: preset)
        }
    }

    /// Find the first preset where the card fits
    /// - Parameter document: The share image document to measure
    /// - Returns: The first fitting preset measurement, or nil if none fit
    public static func findFirstFit(
        document: ShareImageDocument
    ) -> Measurement? {
        for preset in ShareCanvasPreset.orderedByHeight {
            let measurement = measure(document: document, for: preset)
            if measurement.fitsInCanvas {
                return measurement
            }
        }
        return nil
    }

    // MARK: - Private Helpers

    /// Estimate card height when ImageRenderer fails
    /// This is a fallback that makes rough estimates based on content
    private static func estimateHeight(
        for document: ShareImageDocument,
        scale: CGFloat
    ) -> CGFloat {
        var height: CGFloat = 0

        // Base padding
        height += 24 * scale

        // Post content (rough estimate)
        if document.includePostDetails {
            // Avatar row
            height += 50 * scale
            // Content text (estimate 20px per 50 characters)
            let contentLength = document.selectedPost.content.characters.count
            let estimatedLines = max(1, contentLength / 50)
            height += CGFloat(estimatedLines) * 22 * scale
            // Stats
            height += 20 * scale
            // Media (if any)
            if !document.selectedPost.mediaThumbnails.isEmpty {
                height += 200 * scale
            }
            // Link preview (if any)
            if document.selectedPost.linkPreviewData != nil {
                height += 100 * scale
            }
        }

        // Comments
        let commentCount = document.allComments.count
        if commentCount > 0 {
            // Divider
            height += 12 * scale
            // Each comment (rough estimate)
            height += CGFloat(commentCount) * 80 * scale
        }

        // Watermark
        if document.showWatermark {
            height += 30 * scale
        }

        return height
    }
}
