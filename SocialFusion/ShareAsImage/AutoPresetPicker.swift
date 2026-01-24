import SwiftUI

/// Automatically selects the best canvas preset for a share image document
@MainActor
public struct AutoPresetPicker {

    /// Result of the auto-selection process
    public struct SelectionResult: Sendable {
        /// The selected preset
        public let preset: ShareCanvasPreset
        /// The evaluation that led to this selection
        public let evaluation: PresetEvaluator.Evaluation
        /// Whether pagination is recommended
        public let shouldPaginate: Bool
        /// All evaluations considered
        public let allEvaluations: [PresetEvaluator.Evaluation]
    }

    // MARK: - Configuration

    /// Pagination threshold: if 9:16 card exceeds this multiplier of canvas height, paginate
    private static let paginationHeightMultiplier: CGFloat = 1.75

    /// Default fallback preset when nothing fits
    private static let fallbackPreset: ShareCanvasPreset = .ratio9x16

    // MARK: - Public API

    /// Select the best preset for a document using two-pass evaluation
    /// - Parameter document: The share image document to evaluate
    /// - Returns: Selection result with chosen preset and pagination recommendation
    public static func selectPreset(
        for document: ShareImageDocument
    ) -> SelectionResult {
        // Calculate thread length for bias
        let threadLength = calculateThreadLength(for: document)

        // PASS A: Measure content at each preset's card width
        let measurements = CardMeasurer.measureAll(document: document)

        // PASS B: Score each preset
        let evaluations = PresetEvaluator.evaluateAll(
            measurements: measurements,
            threadLength: threadLength
        )

        // Find best valid preset
        if let bestEvaluation = PresetEvaluator.findBest(evaluations: evaluations) {
            return SelectionResult(
                preset: bestEvaluation.preset,
                evaluation: bestEvaluation,
                shouldPaginate: false,
                allEvaluations: evaluations
            )
        }

        // No valid preset found - check if pagination is needed
        // Use 9:16 and check if pagination threshold is exceeded
        let tallestPreset = fallbackPreset
        let tallestMeasurement = measurements.first { $0.preset == tallestPreset }
            ?? measurements.last!

        let tallestEvaluation = evaluations.first { $0.preset == tallestPreset }
            ?? evaluations.last!

        let shouldPaginate = checkPaginationNeeded(
            measurement: tallestMeasurement,
            preset: tallestPreset
        )

        return SelectionResult(
            preset: tallestPreset,
            evaluation: tallestEvaluation,
            shouldPaginate: shouldPaginate,
            allEvaluations: evaluations
        )
    }

    /// Quick check if a document will require pagination without full measurement
    /// - Parameter document: The share image document to check
    /// - Returns: True if pagination is likely needed
    public static func willLikelyNeedPagination(
        for document: ShareImageDocument
    ) -> Bool {
        // Heuristic: more than 5 comments likely needs pagination
        let commentCount = document.allComments.count
        return commentCount > 5
    }

    // MARK: - Private Helpers

    private static func calculateThreadLength(
        for document: ShareImageDocument
    ) -> Int {
        // Count: 1 for the main post + number of comments
        let postCount = document.includePostDetails ? 1 : 0
        let commentCount = document.allComments.count
        return postCount + commentCount
    }

    private static func checkPaginationNeeded(
        measurement: CardMeasurer.Measurement,
        preset: ShareCanvasPreset
    ) -> Bool {
        // Only paginate with 9:16 preset
        guard preset == .ratio9x16 else { return false }

        let canvasSize = preset.canvasSize(shortSide: 1080)
        let threshold = canvasSize.height * paginationHeightMultiplier

        return measurement.cardHeight > threshold
    }
}
