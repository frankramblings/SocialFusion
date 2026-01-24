import Foundation
import CoreGraphics

/// Evaluates canvas presets for share images, scoring them based on fit and waste
public struct PresetEvaluator {

    /// Evaluation result for a single preset
    public struct Evaluation: Sendable {
        /// The preset being evaluated
        public let preset: ShareCanvasPreset
        /// Whether the card fits within the canvas safe area
        public let isValid: Bool
        /// Ratio of wasted (empty) space to total canvas height (0.0 - 1.0)
        public let wasteRatio: CGFloat
        /// Final score (lower is better, infinity if invalid)
        public let score: Double
        /// The measured card height
        public let cardHeight: CGFloat
        /// The available height in the canvas
        public let availableHeight: CGFloat
    }

    // MARK: - Configuration

    /// Short side dimension for calculations
    private static let shortSide: CGFloat = 1080

    // MARK: - Bias Configuration

    /// Bias toward 4:3 for short posts (negative = prefer)
    private static let bias4x3Short: Double = -0.02

    /// Bias toward 9:16 for long threads (negative = prefer)
    private static let bias9x16Long: Double = -0.03

    /// Thread length threshold for "long thread" bias
    private static let longThreadThreshold = 3

    // MARK: - Public API

    /// Evaluate a single preset for a given measurement and thread context
    /// - Parameters:
    ///   - measurement: The card measurement for this preset
    ///   - threadLength: Number of posts/comments in the thread
    /// - Returns: Evaluation result with validity, waste ratio, and score
    public static func evaluate(
        measurement: CardMeasurer.Measurement,
        threadLength: Int
    ) -> Evaluation {
        let preset = measurement.preset
        let cardHeight = measurement.cardHeight
        let availableHeight = SafeInsetCalculator.maxCardHeight(
            for: preset,
            shortSide: shortSide
        )

        // Check validity
        let isValid = cardHeight <= availableHeight

        // Calculate waste ratio
        let wasteRatio: CGFloat
        if isValid {
            wasteRatio = (availableHeight - cardHeight) / availableHeight
        } else {
            wasteRatio = 0  // Doesn't matter for invalid presets
        }

        // Calculate score
        let score = calculateScore(
            preset: preset,
            isValid: isValid,
            wasteRatio: wasteRatio,
            threadLength: threadLength
        )

        return Evaluation(
            preset: preset,
            isValid: isValid,
            wasteRatio: wasteRatio,
            score: score,
            cardHeight: cardHeight,
            availableHeight: availableHeight
        )
    }

    /// Evaluate all presets for a document
    /// - Parameters:
    ///   - measurements: Array of measurements for each preset
    ///   - threadLength: Number of posts/comments in the thread
    /// - Returns: Array of evaluations, one per preset
    public static func evaluateAll(
        measurements: [CardMeasurer.Measurement],
        threadLength: Int
    ) -> [Evaluation] {
        measurements.map { measurement in
            evaluate(measurement: measurement, threadLength: threadLength)
        }
    }

    /// Find the best preset from evaluations (lowest valid score)
    /// - Parameter evaluations: Array of preset evaluations
    /// - Returns: The best evaluation, or nil if none are valid
    public static func findBest(
        evaluations: [Evaluation]
    ) -> Evaluation? {
        evaluations
            .filter { $0.isValid }
            .min { $0.score < $1.score }
    }

    // MARK: - Private Helpers

    private static func calculateScore(
        preset: ShareCanvasPreset,
        isValid: Bool,
        wasteRatio: CGFloat,
        threadLength: Int
    ) -> Double {
        // Invalid presets get infinity score
        guard isValid else {
            return .infinity
        }

        var score = Double(wasteRatio)

        // Apply bias terms
        switch preset {
        case .ratio4x3:
            // Prefer 4:3 for short content (single posts)
            if threadLength <= 1 {
                score += bias4x3Short
            }

        case .ratio1x1:
            // No special bias for square
            break

        case .ratio4x5:
            // No special bias for 4:5
            break

        case .ratio9x16:
            // Prefer 9:16 for long threads
            if threadLength >= longThreadThreshold {
                score += bias9x16Long
            }
        }

        return score
    }
}
