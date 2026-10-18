import CoreGraphics
import Foundation
import Testing
@testable import Keeproll

/// Synthetic 32 × 32 frames for the Accidental Shots and Smart Trim rules.
nonisolated private enum Frame {
    static let side = ExposureStats.side

    /// Builds an RGBA buffer from a colour function of (x, y).
    static func make(_ color: (Int, Int) -> (UInt8, UInt8, UInt8)) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let (r, g, b) = color(x, y)
                let i = (y * side + x) * 4
                pixels[i] = r; pixels[i + 1] = g; pixels[i + 2] = b
            }
        }
        return pixels
    }

    static func stats(_ color: (Int, Int) -> (UInt8, UInt8, UInt8)) -> ExposureStats {
        AccidentalShotEngine.stats(rgba: make(color), side: side)!
    }

    /// A detailed, ordinary scene: a grey checkerboard.
    static func scene(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
        (x + y) % 2 == 0 ? (60, 70, 80) : (180, 190, 200)
    }
}

struct AccidentalShotTests {
    @Test func blackFrameIsTooDark() {
        let stats = Frame.stats { _, _ in (6, 5, 7) }
        #expect(AccidentalShotEngine.verdict(stats: stats, sharpness: 0.05, isFavorite: false) == .tooDark)
    }

    @Test func nightSkyWithTheMoonIsKept() {
        // Dark everywhere, but a few bright pixels: a real photo, not a pocket shot.
        let stats = Frame.stats { x, y in (x >= 20 && x < 23 && y >= 5 && y < 7) ? (245, 245, 235) : (8, 10, 18) }
        #expect(stats.p98 < AccidentalShotEngine.darkP98)
        #expect(AccidentalShotEngine.verdict(stats: stats, sharpness: 0.3, isFavorite: false) == nil)
    }

    @Test func flatColourIsBlank() {
        let stats = Frame.stats { _, _ in (128, 126, 120) }
        #expect(AccidentalShotEngine.verdict(stats: stats, sharpness: 0.04, isFavorite: false) == .blank)
    }

    @Test func clearSkyGradientIsKept() {
        let stats = Frame.stats { _, y in (UInt8(90 + y * 3), UInt8(140 + y * 2), 230) }
        #expect(stats.standardDeviation >= AccidentalShotEngine.blankDeviation)
        #expect(AccidentalShotEngine.verdict(stats: stats, sharpness: 0.05, isFavorite: false) == nil)
    }

    @Test func warmBlobOnTheEdgeIsAFinger() {
        let stats = Frame.stats { x, y in x < 13 ? (205, 120, 95) : Frame.scene(x, y) }
        #expect(stats.fingerScore >= AccidentalShotEngine.fingerThreshold)
        #expect(AccidentalShotEngine.verdict(stats: stats, sharpness: 0.3, isFavorite: false) == .finger)
    }

    @Test func warmFaceInTheMiddleIsNotAFinger() {
        // A close-up face: warm, but it doesn't reach any edge.
        let stats = Frame.stats { x, y in (8..<24).contains(x) && (8..<24).contains(y) ? (205, 140, 110) : Frame.scene(x, y) }
        #expect(AccidentalShotEngine.verdict(stats: stats, sharpness: 0.3, isFavorite: false) == nil)
    }

    @Test func sunsetFillingTheFrameIsNotAFinger() {
        let stats = Frame.stats { _, y in (UInt8(230 - y), UInt8(130 - y), 60) }
        #expect(stats.fingerScore == 0)
        #expect(AccidentalShotEngine.verdict(stats: stats, sharpness: 0.1, isFavorite: false) == nil)
    }

    @Test func fingerInTheCornerIsAFinger() {
        let stats = Frame.stats { x, y in x < 16 && y >= 14 ? (215, 115, 90) : Frame.scene(x, y) }
        #expect(AccidentalShotEngine.verdict(stats: stats, sharpness: 0.3, isFavorite: false) == .finger)
    }

    @Test func objectOnAWarmBackgroundIsNotAFinger() {
        // The look-alike the simulator caught: a peach backdrop touching every edge.
        let stats = Frame.stats { x, y in
            let dx = Double(x) - 15.5, dy = Double(y) - 15.5
            return dx * dx / 100 + dy * dy / 49 < 1 ? (40, 110, 100) : (240, 160, 140)
        }
        #expect(stats.fingerScore == 0)
        #expect(AccidentalShotEngine.verdict(stats: stats, sharpness: 0.2, isFavorite: false) == nil)
    }

    @Test func sunsetSkyOverDarkGroundIsNotAFinger() {
        let stats = Frame.stats { _, y in y < 16 ? (250, UInt8(120 + y * 2), 60) : (30, 30, 40) }
        #expect(stats.fingerScore == 0)
    }

    @Test func sandyBeachIsNotAFinger() {
        let stats = Frame.stats { x, y in y >= 16 ? (194, 178, 128) : Frame.scene(x, y) }
        #expect(stats.fingerScore == 0)
    }

    @Test func favouritesAreNeverFlagged() {
        let stats = Frame.stats { _, _ in (0, 0, 0) }
        #expect(AccidentalShotEngine.verdict(stats: stats, sharpness: 0, isFavorite: true) == nil)
    }

    @Test func statsWorkOnARealCGImage() throws {
        let pixels = Frame.make { _, _ in (3, 3, 3) }
        let data = Data(pixels) as CFData
        let provider = try #require(CGDataProvider(data: data))
        let image = try #require(CGImage(width: 32, height: 32, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 128,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let stats = try #require(AccidentalShotEngine.stats(image))
        #expect(stats.maximum < 10)
    }
}

struct SmartTrimTests {
    private let dark = Frame.stats { _, _ in (4, 4, 4) }
    private let live = Frame.stats(Frame.scene)

    /// One sample a second; `deadAt` says which seconds are dark.
    private func samples(duration: Int, deadAt: (Int) -> Bool) -> [TrimSample] {
        (0..<duration).map { TrimSample(time: Double($0) + 0.5, stats: deadAt($0) ? dark : live) }
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
        let stats = ExposureStats(mean: 10, standardDeviation: 3, p98: 20, maximum: 40, fingerScore: 7)
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
