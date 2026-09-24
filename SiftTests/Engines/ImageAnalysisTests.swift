import Testing
@testable import Sift

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

    @Test func featureDistanceMatchesEuclid() {
        #expect(FeaturePrinter.distance([0, 0], [3, 4]) == 5)
        #expect(FeaturePrinter.distance([1], [1, 2]) == .infinity)
    }
}
