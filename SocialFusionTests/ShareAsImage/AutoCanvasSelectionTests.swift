import XCTest
@testable import SocialFusion

/// Tests for the automatic canvas selection pipeline
final class AutoCanvasSelectionTests: XCTestCase {

    // MARK: - ShareCanvasPreset Tests

    func testCanvasPresetAspectRatios() {
        XCTAssertEqual(ShareCanvasPreset.ratio4x3.aspectRatio, 4.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(ShareCanvasPreset.ratio1x1.aspectRatio, 1.0, accuracy: 0.001)
        XCTAssertEqual(ShareCanvasPreset.ratio4x5.aspectRatio, 4.0 / 5.0, accuracy: 0.001)
        XCTAssertEqual(ShareCanvasPreset.ratio9x16.aspectRatio, 9.0 / 16.0, accuracy: 0.001)
    }

    func testCanvasPresetOrientation() {
        XCTAssertTrue(ShareCanvasPreset.ratio4x3.isLandscape)
        XCTAssertFalse(ShareCanvasPreset.ratio4x3.isPortrait)

        XCTAssertFalse(ShareCanvasPreset.ratio1x1.isLandscape)
        XCTAssertFalse(ShareCanvasPreset.ratio1x1.isPortrait)

        XCTAssertFalse(ShareCanvasPreset.ratio4x5.isLandscape)
        XCTAssertTrue(ShareCanvasPreset.ratio4x5.isPortrait)

        XCTAssertFalse(ShareCanvasPreset.ratio9x16.isLandscape)
        XCTAssertTrue(ShareCanvasPreset.ratio9x16.isPortrait)
    }

    func testCanvasPresetSizeCalculation() {
        let shortSide: CGFloat = 1080

        // 4:3 - landscape, so height is short side
        let size4x3 = ShareCanvasPreset.ratio4x3.canvasSize(shortSide: shortSide)
        XCTAssertEqual(size4x3.height, shortSide)
        XCTAssertEqual(size4x3.width, round(shortSide * 4.0 / 3.0), accuracy: 1)

        // 1:1 - square, both sides equal
        let size1x1 = ShareCanvasPreset.ratio1x1.canvasSize(shortSide: shortSide)
        XCTAssertEqual(size1x1.width, shortSide)
        XCTAssertEqual(size1x1.height, shortSide)

        // 4:5 - portrait, so width is short side
        let size4x5 = ShareCanvasPreset.ratio4x5.canvasSize(shortSide: shortSide)
        XCTAssertEqual(size4x5.width, shortSide)
        XCTAssertEqual(size4x5.height, round(shortSide / (4.0 / 5.0)), accuracy: 1)

        // 9:16 - portrait, so width is short side
        let size9x16 = ShareCanvasPreset.ratio9x16.canvasSize(shortSide: shortSide)
        XCTAssertEqual(size9x16.width, shortSide)
        XCTAssertEqual(size9x16.height, round(shortSide / (9.0 / 16.0)), accuracy: 1)
    }

    func testCanvasPresetDisplayNames() {
        XCTAssertEqual(ShareCanvasPreset.ratio4x3.displayName, "4:3")
        XCTAssertEqual(ShareCanvasPreset.ratio1x1.displayName, "1:1")
        XCTAssertEqual(ShareCanvasPreset.ratio4x5.displayName, "4:5")
        XCTAssertEqual(ShareCanvasPreset.ratio9x16.displayName, "9:16")
    }

    // MARK: - SafeInsetCalculator Tests

    func testSafeInsetsMinimum() {
        // With a very small short side, insets should still be at least 64px
        let insets = SafeInsetCalculator.computeSafeInsets(shortSide: 100)
        XCTAssertGreaterThanOrEqual(insets.x, 64)
        XCTAssertGreaterThanOrEqual(insets.y, 64 * 0.9)  // Vertical has compression
    }

    func testSafeInsetsAtStandardSize() {
        let insets = SafeInsetCalculator.computeSafeInsets(shortSide: 1080)

        // Base inset = 1080 * 0.08 = 86.4
        // Horizontal = 86.4 * 1.15 = ~99
        // Vertical = 86.4 * 0.90 = ~78

        XCTAssertGreaterThan(insets.x, insets.y, "Horizontal inset should be larger due to iMessage bias")
        XCTAssertEqual(insets.totalHorizontal, insets.x * 2)
        XCTAssertEqual(insets.totalVertical, insets.y * 2)
    }

    func testSafeInsetsScaleWithSize() {
        let smallInsets = SafeInsetCalculator.computeSafeInsets(shortSide: 500)
        let largeInsets = SafeInsetCalculator.computeSafeInsets(shortSide: 2000)

        // Larger canvas should have larger insets
        XCTAssertGreaterThan(largeInsets.x, smallInsets.x)
        XCTAssertGreaterThan(largeInsets.y, smallInsets.y)
    }

    func testContentAreaCalculation() {
        let shortSide: CGFloat = 1080
        let preset = ShareCanvasPreset.ratio4x3
        let canvasSize = preset.canvasSize(shortSide: shortSide)
        let contentArea = SafeInsetCalculator.contentArea(for: preset, shortSide: shortSide)
        let insets = SafeInsetCalculator.computeSafeInsets(for: preset, shortSide: shortSide)

        XCTAssertEqual(contentArea.width, canvasSize.width - insets.totalHorizontal, accuracy: 1)
        XCTAssertEqual(contentArea.height, canvasSize.height - insets.totalVertical, accuracy: 1)
    }

    func testMaxCardDimensions() {
        let shortSide: CGFloat = 1080
        let preset = ShareCanvasPreset.ratio9x16

        let maxWidth = SafeInsetCalculator.maxCardWidth(for: preset, shortSide: shortSide)
        let maxHeight = SafeInsetCalculator.maxCardHeight(for: preset, shortSide: shortSide)

        let canvasSize = preset.canvasSize(shortSide: shortSide)
        XCTAssertLessThan(maxWidth, canvasSize.width)
        XCTAssertLessThan(maxHeight, canvasSize.height)
    }

    // MARK: - PresetEvaluator Tests

    func testEvaluationValidity() {
        // Create a mock measurement that fits
        let fittingMeasurement = CardMeasurer.Measurement(
            preset: .ratio4x3,
            cardWidth: 800,
            cardHeight: 600,
            fitsInCanvas: true
        )

        let evaluation = PresetEvaluator.evaluate(measurement: fittingMeasurement, threadLength: 1)
        XCTAssertTrue(evaluation.isValid)
        XCTAssertLessThan(evaluation.score, Double.infinity)

        // Create a mock measurement that doesn't fit
        let overflowMeasurement = CardMeasurer.Measurement(
            preset: .ratio4x3,
            cardWidth: 800,
            cardHeight: 2000,  // Too tall
            fitsInCanvas: false
        )

        let overflowEvaluation = PresetEvaluator.evaluate(measurement: overflowMeasurement, threadLength: 1)
        XCTAssertFalse(overflowEvaluation.isValid)
        XCTAssertEqual(overflowEvaluation.score, Double.infinity)
    }

    func testEvaluationWasteRatio() {
        let preset = ShareCanvasPreset.ratio4x3
        let maxHeight = SafeInsetCalculator.maxCardHeight(for: preset, shortSide: 1080)

        // Card that uses half the available height
        let halfHeightMeasurement = CardMeasurer.Measurement(
            preset: preset,
            cardWidth: 800,
            cardHeight: maxHeight / 2,
            fitsInCanvas: true
        )

        let evaluation = PresetEvaluator.evaluate(measurement: halfHeightMeasurement, threadLength: 1)
        XCTAssertEqual(evaluation.wasteRatio, 0.5, accuracy: 0.05)
    }

    func testEvaluationBiasFor4x3Short() {
        // 4:3 should be biased for short content (threadLength <= 1)
        let measurement = CardMeasurer.Measurement(
            preset: .ratio4x3,
            cardWidth: 800,
            cardHeight: 500,
            fitsInCanvas: true
        )

        let shortEval = PresetEvaluator.evaluate(measurement: measurement, threadLength: 1)
        let longEval = PresetEvaluator.evaluate(measurement: measurement, threadLength: 5)

        // Short thread should have lower (better) score for 4:3
        XCTAssertLessThan(shortEval.score, longEval.score)
    }

    func testEvaluationBiasFor9x16Long() {
        // 9:16 should be biased for long content (threadLength >= 3)
        let measurement = CardMeasurer.Measurement(
            preset: .ratio9x16,
            cardWidth: 800,
            cardHeight: 1200,
            fitsInCanvas: true
        )

        let shortEval = PresetEvaluator.evaluate(measurement: measurement, threadLength: 1)
        let longEval = PresetEvaluator.evaluate(measurement: measurement, threadLength: 5)

        // Long thread should have lower (better) score for 9:16
        XCTAssertLessThan(longEval.score, shortEval.score)
    }

    func testFindBestPreset() {
        let evaluations = [
            PresetEvaluator.Evaluation(
                preset: .ratio4x3,
                isValid: true,
                wasteRatio: 0.3,
                score: 0.28,
                cardHeight: 500,
                availableHeight: 714
            ),
            PresetEvaluator.Evaluation(
                preset: .ratio1x1,
                isValid: true,
                wasteRatio: 0.2,
                score: 0.2,
                cardHeight: 700,
                availableHeight: 875
            ),
            PresetEvaluator.Evaluation(
                preset: .ratio4x5,
                isValid: true,
                wasteRatio: 0.1,
                score: 0.1,  // Lowest score
                cardHeight: 950,
                availableHeight: 1056
            ),
            PresetEvaluator.Evaluation(
                preset: .ratio9x16,
                isValid: false,  // Invalid
                wasteRatio: 0,
                score: .infinity,
                cardHeight: 2000,
                availableHeight: 1760
            )
        ]

        let best = PresetEvaluator.findBest(evaluations: evaluations)
        XCTAssertNotNil(best)
        XCTAssertEqual(best?.preset, .ratio4x5)  // Lowest valid score
    }

    func testFindBestReturnsNilWhenNoneValid() {
        let evaluations = [
            PresetEvaluator.Evaluation(
                preset: .ratio4x3,
                isValid: false,
                wasteRatio: 0,
                score: .infinity,
                cardHeight: 2000,
                availableHeight: 714
            ),
            PresetEvaluator.Evaluation(
                preset: .ratio1x1,
                isValid: false,
                wasteRatio: 0,
                score: .infinity,
                cardHeight: 2000,
                availableHeight: 875
            )
        ]

        let best = PresetEvaluator.findBest(evaluations: evaluations)
        XCTAssertNil(best)
    }

    // MARK: - Integration Tests

    func testAllPresetsOrderedByHeight() {
        // Verify presets are correctly ordered from shortest to tallest canvas
        let shortSide: CGFloat = 1080
        var heights: [CGFloat] = []

        for preset in ShareCanvasPreset.orderedByHeight {
            let size = preset.canvasSize(shortSide: shortSide)
            heights.append(size.height)
        }

        // Each height should be >= previous
        for i in 1..<heights.count {
            XCTAssertGreaterThanOrEqual(heights[i], heights[i-1],
                "Presets not ordered by height: \(heights[i-1]) > \(heights[i])")
        }
    }

    func testAllCasesCount() {
        XCTAssertEqual(ShareCanvasPreset.allCases.count, 4)
    }
}
