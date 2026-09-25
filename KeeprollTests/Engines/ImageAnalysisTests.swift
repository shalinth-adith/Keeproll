import Testing
@testable import Keeproll

struct ImageAnalysisTests {
    @Test func identicalImagesHaveIdenticalHashes() throws {
        let a = try #require(ImageAnalysis.dHash(TestImages.scene()))
        let b = try #require(ImageAnalysis.dHash(TestImages.scene()))
        #expect(a == b)
    }

    @Test func brighterCopyStaysWithinDuplicateDistance() throws {
        // A re-saved / slightly edited copy should still count as a duplicate.
        let a = try #require(ImageAnalysis.dHash(TestImages.scene()))
        let b = try #require(ImageAnalysis.dHash(TestImages.scene(brightness: 12)))
        #expect(ImageAnalysis.hamming(a, b) <= SimilarityConfig.standard.duplicateHashDistance)
    }

    @Test func differentScenesAreFarApart() throws {
        let a = try #require(ImageAnalysis.dHash(TestImages.scene()))
        let b = try #require(ImageAnalysis.dHash(TestImages.checkerboard(cell: 16)))
        #expect(ImageAnalysis.hamming(a, b) > SimilarityConfig.standard.fallbackHashDistance)
    }

    @Test func sharpImageScoresHigherThanFlatOne() {
        let sharp = ImageAnalysis.sharpness(TestImages.checkerboard())
        let flat = ImageAnalysis.sharpness(TestImages.flat())
        #expect(sharp > SimilarityConfig.standard.blurThreshold)
        #expect(flat < SimilarityConfig.standard.blurThreshold)
    }

    // F4: the focus score measures focus, not contrast.
    @Test func blurIsDetectedWhateverTheContrast() {
        let threshold = SimilarityConfig.standard.blurThreshold
        let sharp = ImageAnalysis.sharpness(TestImages.scene())
        let blurred = ImageAnalysis.sharpness(TestImages.blurred(TestImages.scene()))
        let darkBlurred = ImageAnalysis.sharpness(TestImages.blurred(TestImages.scene(scale: 0.4)))
        let lowContrastSharp = ImageAnalysis.sharpness(TestImages.scene(scale: 0.25))
        #expect(sharp > threshold, "sharp \(sharp)")
        #expect(blurred < threshold, "blurred \(blurred)")
        #expect(darkBlurred < threshold, "dark blurred \(darkBlurred)")
        #expect(lowContrastSharp > threshold, "low-contrast sharp \(lowContrastSharp)")
    }

    @Test func featureDistanceMatchesEuclid() {
        #expect(FeaturePrinter.distance([0, 0], [3, 4]) == 5)
        #expect(FeaturePrinter.distance([1], [1, 2]) == .infinity)
    }
}
