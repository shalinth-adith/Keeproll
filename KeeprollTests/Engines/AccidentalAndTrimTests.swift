import CoreGraphics
import Foundation
import Testing
@testable import Keeproll

/// Synthetic 96 × 96 frames for the Accidental Shots and Smart Trim rules. Colour
/// functions take (u, v) in 0..<1, so tests don't depend on the render size.
nonisolated private enum Frame {
    static let side = ExposureStats.colourSide
    typealias RGB = (UInt8, UInt8, UInt8)

    static func make(_ color: (Double, Double) -> RGB) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let (r, g, b) = color((Double(x) + 0.5) / Double(side), (Double(y) + 0.5) / Double(side))
                let i = (y * side + x) * 4
                pixels[i] = r; pixels[i + 1] = g; pixels[i + 2] = b
            }
        }
        return pixels
    }

    static func stats(_ color: (Double, Double) -> RGB) -> ExposureStats {
        AccidentalShotEngine.stats(rgba: make(color), side: side)!
    }

    /// A detailed, ordinary scene: a grey checkerboard of 32 × 32 cells.
    static func scene(_ u: Double, _ v: Double) -> RGB {
        (Int(u * 32) + Int(v * 32)) % 2 == 0 ? (60, 70, 80) : (180, 190, 200)
    }

    /// A smooth, darkish grey scene (no edges of its own).
    static func smooth(_ u: Double, _ v: Double) -> RGB {
        let g = UInt8(50 + 40 * u)
        return (g, g, g)
    }

    /// Mixes two colours: t = 0 gives `a`, t = 1 gives `b`.
    static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        let t = min(max(t, 0), 1)
        func m(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8((Double(x) * (1 - t) + Double(y) * t).rounded()) }
        return (m(a.0, b.0), m(a.1, b.1), m(a.2, b.2))
    }

    static let skin: RGB = (205, 120, 95)
}

struct AccidentalShotTests {
    private func verdict(_ stats: ExposureStats, sharpness: Float = 0.3) -> AccidentalReason? {
        AccidentalShotEngine.verdict(stats: stats, sharpness: sharpness, isFavorite: false)
    }

    @Test func blackFrameIsTooDark() {
        #expect(verdict(Frame.stats { _, _ in (6, 5, 7) }, sharpness: 0.05) == .tooDark)
    }

    @Test func pocketShotWithAHotPixelIsStillTooDark() {
        let stats = Frame.stats { u, v in u > 0.5 && u < 0.511 && v > 0.5 && v < 0.511 ? (255, 255, 255) : (6, 6, 6) }
        #expect(verdict(stats, sharpness: 0.05) == .tooDark)
    }

    @Test func nightSkyWithTheMoonIsKept() {
        let stats = Frame.stats { u, v in (0.6..<0.7).contains(u) && (0.15..<0.22).contains(v) ? (245, 245, 235) : (8, 10, 18) }
        #expect(stats.p98 < AccidentalShotEngine.darkP98)
        #expect(verdict(stats) == nil)
    }

    @Test func starfieldIsKept() {
        // QA A2: scattered single stars average away when shrunk; counting lit pixels keeps them.
        let stats = Frame.stats { u, v in
            Int(u * 96) % 12 == 0 && Int(v * 96) % 12 == 0 ? (240, 240, 240) : (10, 10, 14)
        }
        #expect(stats.maximum < AccidentalShotEngine.darkMaximum) // the old rule would have flagged it
        #expect(verdict(stats) == nil)
    }

    @Test func flatGreyIsBlank() {
        #expect(verdict(Frame.stats { _, _ in (128, 126, 120) }, sharpness: 0.04) == .blank)
    }

    @Test func colourSwatchIsNotBlank() {
        // QA A4: a deliberate photo of one colour.
        #expect(verdict(Frame.stats { _, _ in (40, 120, 200) }, sharpness: 0.04) == nil)
    }

    @Test func clearSkyGradientIsKept() {
        let stats = Frame.stats { _, v in (UInt8(90 + v * 93), UInt8(140 + v * 62), 230) }
        #expect(stats.standardDeviation >= AccidentalShotEngine.blankDeviation)
        #expect(verdict(stats, sharpness: 0.05) == nil)
    }

    @Test func softFingerOnTheSideIsAFinger() {
        let stats = Frame.stats { u, v in Frame.mix(Frame.skin, Frame.smooth(u, v), (u - 0.30) / 0.18) }
        #expect(stats.fingerScore >= AccidentalShotEngine.fingerThreshold)
        #expect(verdict(stats) == .finger)
    }

    @Test func softFingerInTheCornerIsAFinger() {
        let stats = Frame.stats { u, v in
            let d = ((u * u) + (1 - v) * (1 - v)).squareRoot()
            return Frame.mix((215, 115, 90), Frame.smooth(u, v), (d - 0.55) / 0.15)
        }
        #expect(verdict(stats) == .finger)
    }

    @Test func crispOrangeTopIsNotAFinger() {
        // QA A1: a portrait with an orange top along the bottom. Its edge is in focus.
        let stats = Frame.stats { u, v in v >= 0.66 ? (224, 102, 42) : Frame.smooth(u, v) }
        #expect(stats.fingerScore == 0)
        #expect(verdict(stats) == nil)
    }

    @Test func warmFaceInTheMiddleIsNotAFinger() {
        let stats = Frame.stats { u, v in (0.25..<0.75).contains(u) && (0.25..<0.75).contains(v) ? (205, 140, 110) : Frame.scene(u, v) }
        #expect(verdict(stats) == nil)
    }

    @Test func sunsetFillingTheFrameIsNotAFinger() {
        let stats = Frame.stats { _, v in (UInt8(230 - v * 31), UInt8(130 - v * 31), 60) }
        #expect(stats.fingerScore == 0)
        #expect(verdict(stats, sharpness: 0.1) == nil)
    }

    @Test func objectOnAWarmBackgroundIsNotAFinger() {
        let stats = Frame.stats { u, v in
            let dx = u - 0.5, dy = v - 0.5
            return dx * dx / 0.1 + dy * dy / 0.05 < 1 ? (40, 110, 100) : (240, 160, 140)
        }
        #expect(stats.fingerScore == 0)
        #expect(verdict(stats, sharpness: 0.2) == nil)
    }

    @Test func sunsetSkyOverDarkGroundIsNotAFinger() {
        let stats = Frame.stats { _, v in v < 0.5 ? (250, UInt8(120 + v * 120), 60) : (30, 30, 40) }
        #expect(stats.fingerScore == 0)
    }

    @Test func sandyBeachIsNotAFinger() {
        let stats = Frame.stats { u, v in v >= 0.5 ? (194, 178, 128) : Frame.scene(u, v) }
        #expect(stats.fingerScore == 0)
    }

    @Test func favouritesAreNeverFlagged() {
        let stats = Frame.stats { _, _ in (0, 0, 0) }
        #expect(AccidentalShotEngine.verdict(stats: stats, sharpness: 0, isFavorite: true) == nil)
    }

    @Test func statsWorkOnARealCGImage() throws {
        var pixels = [UInt8](repeating: 3, count: 32 * 32 * 4)
        for i in stride(from: 3, to: pixels.count, by: 4) { pixels[i] = 255 }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(width: 32, height: 32, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 128,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let stats = try #require(AccidentalShotEngine.stats(image))
        #expect(stats.maximum < 10)
        #expect(stats.litPerTenThousand == 0)
    }
}

struct SmartTrimTests {
    private let dark = Frame.stats { _, _ in (4, 4, 4) }
    private let live = Frame.stats(Frame.scene)

    /// One sample a second; `deadAt` says which seconds are dark, `loudAt` which have sound.
    private func samples(duration: Int, loudAt: (Int) -> Bool = { _ in false }, deadAt: (Int) -> Bool) -> [TrimSample] {
        (0..<duration).map { TrimSample(time: Double($0) + 0.5, stats: deadAt($0) ? dark : live, hasSound: loudAt($0)) }
    }

    @Test func darkStretchWithSoundIsKept() {
        // QA T4: a baby monitor at night, or someone talking in the dark.
        let ranges = SmartTrimEngine.deadRanges(samples: samples(duration: 120, loudAt: { $0 >= 30 }) { $0 >= 30 }, duration: 120)
        #expect(ranges.isEmpty)
    }

    @Test func soundOnlyKeepsTheSecondsItCovers() {
        // Dark from 30 s to the end, but someone speaks from 60 s to 70 s.
        let ranges = SmartTrimEngine.deadRanges(samples: samples(duration: 120, loudAt: { (60..<70).contains($0) }) { $0 >= 30 },
                                                duration: 120)
        #expect(ranges == [TrimRange(start: 30, end: 60), TrimRange(start: 70, end: 120)])
    }

    @Test func flatBrightFrameIsNotDead() {
        // A clear sky filmed in silence is still real footage.
        #expect(!SmartTrimEngine.isDead(Frame.stats { _, _ in (120, 170, 235) }))
    }

    @Test func pendingPairsDropWhenEitherSideIsGone() {
        let pairs = [
            TrimPair(originalID: "o1", copyID: "c1", savedBytes: 1, originalDuration: 42, keptDuration: 12),
            TrimPair(originalID: "o2", copyID: "c2", savedBytes: 1, originalDuration: 42, keptDuration: 12),
            TrimPair(originalID: "o3", copyID: "c3", savedBytes: 1, originalDuration: 42, keptDuration: 12),
        ]
        // o1: both exist (waiting). o2: original deleted (done). o3: copy deleted (offer the original again).
        let live = ScanStore.livePairs(pairs, existing: ["o1", "c1", "c2", "o3"])
        #expect(live.map(\.originalID) == ["o1"])
    }

    @Test func pocketTailIsTrimmed() {
        let ranges = SmartTrimEngine.deadRanges(samples: samples(duration: 120) { $0 >= 30 }, duration: 120)
        #expect(ranges.count == 1)
        #expect(abs(ranges[0].start - 30) < 0.01)
        #expect(abs(ranges[0].end - 120) < 0.01)
    }

    @Test func darkStartIsTrimmed() {
        let ranges = SmartTrimEngine.deadRanges(samples: samples(duration: 60) { $0 < 8 }, duration: 60)
        #expect(ranges == [TrimRange(start: 0, end: 8)])
    }

    @Test func briefDarkMomentInTheMiddleIsKept() {
        // A tunnel or the lights going off: 6 s in the middle is below the 10 s bar.
        let ranges = SmartTrimEngine.deadRanges(samples: samples(duration: 60) { (20..<26).contains($0) }, duration: 60)
        #expect(ranges.isEmpty)
    }

    @Test func longDeadMiddleIsCut() {
        let ranges = SmartTrimEngine.deadRanges(samples: samples(duration: 90) { (30..<50).contains($0) }, duration: 90)
        #expect(ranges == [TrimRange(start: 30, end: 50)])
    }

    @Test func smallShareIsLeftAlone() {
        // 6 s of a 10-minute clip is under 10 %: not worth a re-encoded copy.
        let ranges = SmartTrimEngine.deadRanges(samples: samples(duration: 600) { $0 < 6 }, duration: 600)
        #expect(ranges.isEmpty)
    }

    @Test func shortClipsAreNotChecked() {
        #expect(SmartTrimEngine.deadRanges(samples: samples(duration: 10) { _ in true }, duration: 10).isEmpty)
    }

    @Test func allDeadClipIsOfferedForRemoval() {
        let ranges = SmartTrimEngine.deadRanges(samples: samples(duration: 40) { _ in true }, duration: 40)
        let item = MediaItem(id: "v", kind: .video, creationDate: nil, pixelWidth: 1920, pixelHeight: 1080,
                             duration: 40, isFavorite: false, byteSize: 80_000_000)
        let candidate = TrimCandidate(item: item, deadRanges: ranges)
        #expect(candidate.isAllDead)
        #expect(candidate.estimatedSaving == 80_000_000)
    }

    @Test func savingIsProportionalToTimeCut() {
        let item = MediaItem(id: "v", kind: .video, creationDate: nil, pixelWidth: 1920, pixelHeight: 1080,
                             duration: 100, isFavorite: false, byteSize: 100_000_000)
        let candidate = TrimCandidate(item: item, deadRanges: [TrimRange(start: 0, end: 10), TrimRange(start: 70, end: 100)])
        #expect(candidate.estimatedSaving == 40_000_000)
        #expect(candidate.keptRanges == [TrimRange(start: 10, end: 70)])
        #expect(!candidate.isAllDead)
    }

    @Test func measuredBytesBeatTheTimeEstimate() {
        // 30 s of black in a 42 s clip: by time it's 70 % of the file, but black frames
        // compress to almost nothing, so the measured bytes win and it isn't offered.
        let item = MediaItem(id: "v", kind: .video, creationDate: nil, pixelWidth: 1280, pixelHeight: 720,
                             duration: 42, isFavorite: false, byteSize: 4_700_000)
        let black = TrimCandidate(item: item, deadRanges: [TrimRange(start: 12, end: 42)], deadBytes: 30_000)
        #expect(black.estimatedSaving == 30_000)
        #expect(!black.isWorthOffering)
        let noisy = TrimCandidate(item: item, deadRanges: [TrimRange(start: 12, end: 42)], deadBytes: 2_500_000)
        #expect(noisy.isWorthOffering)
    }

    @Test func wellLitFrozenFramesAreNotDead() {
        // A filmed lecture barely changes but is bright and detailed: never cut.
        #expect(!SmartTrimEngine.isDead(live))
        #expect(SmartTrimEngine.isDead(dark))
    }

    @Test func samplingIsCapped() {
        #expect(SmartTrimEngine.sampleTimes(duration: 60).count == 60)
        #expect(SmartTrimEngine.sampleTimes(duration: 3600).count <= SmartTrimEngine.maximumSamples)
    }

    @Test func exposureAndTrimRecordsRoundTrip() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scan-cache-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let modified = Date(timeIntervalSinceReferenceDate: 500)
        let stats = ExposureStats(mean: 10, standardDeviation: 3, p98: 20, maximum: 40,
                                  litPerTenThousand: 4, saturation: 9, fingerScore: 7)
        let first = ScanCache(url: url)
        await first.store(stats, for: "p", modified: modified)
        await first.store(trim: [TrimRange(start: 0, end: 12.5)], for: "v", modified: modified)
        await first.store(trim: [], for: "w", modified: modified)
        await first.save()

        let second = ScanCache(url: url)
        #expect(await second.exposure(for: "p", modified: modified) == stats)
        #expect(await second.trim(for: "v", modified: modified)?.ranges == [TrimRange(start: 0, end: 12.5)])
        #expect(await second.trim(for: "v", modified: modified)?.deadBytes == nil)
        #expect(await second.trim(for: "w", modified: modified)?.ranges == [])
        #expect(await second.trim(for: "v", modified: Date(timeIntervalSinceReferenceDate: 501)) == nil)
    }
}
