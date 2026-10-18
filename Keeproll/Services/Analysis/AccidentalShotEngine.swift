import CoreGraphics
import Foundation

/// Brightness and colour statistics of a photo, from a 32 × 32 render of the thumbnail the
/// similarity scan already loads (bonus: Accidental Shots). Four bytes per photo, cached.
nonisolated struct ExposureStats: Sendable, Equatable {
    /// Luma, 0–255.
    let mean: UInt8
    let standardDeviation: UInt8
    /// 98th percentile luma: a pocket shot has almost nothing bright in it.
    let p98: UInt8
    /// Brightest pixel. A night sky with the moon has a dark p98 but a bright maximum.
    let maximum: UInt8
    /// 0–255: how much of one edge region is a smooth, warm, skin-lit blob (a finger
    /// over the lens). 255 = the whole region.
    let fingerScore: UInt8

    static let side = 32
}

/// Why a photo looks like it was taken by accident.
nonisolated enum AccidentalReason: String, CaseIterable, Hashable, Sendable {
    /// Almost black: taken in a pocket or bag, or face down.
    case tooDark
    /// A finger covering part of the lens.
    case finger
    /// One flat colour with no detail: a ceiling, a wall, the inside of a case.
    case blank
}

/// A photo flagged as an accidental shot.
nonisolated struct AccidentalShot: Identifiable, Hashable, Sendable {
    var item: MediaItem
    let reason: AccidentalReason
    var id: String { item.id }
}

/// Decides whether a photo is an accidental shot. Pure and deterministic, unit-tested in
/// `AccidentalShotTests`. Deliberately conservative: a real night photo, a clear sky or a
/// close-up portrait must never be flagged, so every rule needs a strong signal.
nonisolated enum AccidentalShotEngine {
    /// p98 below this, with no bright point anywhere, is a pocket or face-down shot.
    static let darkP98: UInt8 = 40
    static let darkMaximum: UInt8 = 100
    /// A frame flatter than this is one colour (a gradient sky is well above it).
    static let blankDeviation: UInt8 = 6
    static let blankSharpness: Float = 0.12
    /// Share of the edge band a finger must cover. The shape and colour rules do most of
    /// the work, so this can admit a corner finger.
    static let fingerThreshold: UInt8 = 115 // ≈ 45 %

    static func verdict(stats: ExposureStats, sharpness: Float, isFavorite: Bool) -> AccidentalReason? {
        if isFavorite { return nil }
        if stats.p98 < darkP98 && stats.maximum < darkMaximum { return .tooDark }
        if stats.fingerScore >= fingerThreshold { return .finger }
        if stats.standardDeviation < blankDeviation && sharpness < blankSharpness
            && stats.p98 &- stats.mean < 12 { return .blank }
        return nil
    }

    // MARK: - Statistics

    /// Renders `image` at 32 × 32 RGBA and measures it.
    static func stats(_ image: CGImage) -> ExposureStats? {
        let side = ExposureStats.side
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? stats(rgba: pixels, side: side) : nil
    }

    /// Statistics of a square RGBA buffer (row-major, 4 bytes per pixel).
    static func stats(rgba: [UInt8], side: Int) -> ExposureStats? {
        let count = side * side
        guard side >= 4, rgba.count >= count * 4 else { return nil }
        var luma = [UInt8](repeating: 0, count: count)
        var histogram = [Int](repeating: 0, count: 256)
        var sum = 0.0, sumSquares = 0.0
        var maximum: UInt8 = 0
        for i in 0..<count {
            let r = Double(rgba[i * 4]), g = Double(rgba[i * 4 + 1]), b = Double(rgba[i * 4 + 2])
            let y = UInt8(min(255, max(0, (0.299 * r + 0.587 * g + 0.114 * b).rounded())))
            luma[i] = y
            histogram[Int(y)] += 1
            sum += Double(y)
            sumSquares += Double(y) * Double(y)
            maximum = max(maximum, y)
        }
        let n = Double(count)
        let mean = sum / n
        let deviation = max(sumSquares / n - mean * mean, 0).squareRoot()
        var p98: UInt8 = 255
        var seen = 0
        let target = Int((n * 0.98).rounded(.up))
        for value in 0..<256 {
            seen += histogram[value]
            if seen >= target { p98 = UInt8(value); break }
        }
        return ExposureStats(mean: UInt8(mean.rounded()), standardDeviation: UInt8(min(255, deviation.rounded())),
                             p98: p98, maximum: maximum,
                             fingerScore: fingerScore(rgba: rgba, luma: luma, side: side))
    }

    /// A finger over the lens is a smooth, out-of-focus, skin-lit (red to orange) blob that
    /// comes in from one side or one corner. Returns how much of the third of the frame
    /// next to that side it covers, scaled to 0–255.
    ///
    /// What rules out look-alikes:
    /// - **Shape.** Only one edge, or two adjacent edges (a corner), may be mostly warm. A
    ///   warm background touches every edge; a sunset or a wooden table touches three or four.
    /// - **Colour.** Red must clearly beat green (skin with light through it), which
    ///   excludes sand, wood and beige walls.
    /// - **Side.** The finger's own edge is left, right or bottom, never the top: the top of
    ///   an upright photo is where skies are.
    static func fingerScore(rgba: [UInt8], luma: [UInt8], side: Int) -> UInt8 {
        var warm = [Bool](repeating: false, count: side * side)
        for y in 0..<side {
            for x in 0..<side {
                let i = y * side + x
                let r = Int(rgba[i * 4]), g = Int(rgba[i * 4 + 1]), b = Int(rgba[i * 4 + 2])
                let isWarm = r >= 70 && r * 10 >= g * 13 && g + 20 >= b && r - b >= 35
                // Smooth: neighbours differ little (a finger is far out of focus).
                var smooth = true
                if x > 0 && x < side - 1 && y > 0 && y < side - 1 {
                    let c = Int(luma[i])
                    let d = abs(c - Int(luma[i - 1])) + abs(c - Int(luma[i + 1]))
                        + abs(c - Int(luma[i - side])) + abs(c - Int(luma[i + side]))
                    smooth = d <= 16
                }
                warm[i] = isWarm && smooth
            }
        }

        enum Edge: CaseIterable { case left, right, top, bottom }
        func coverage(_ edge: Edge) -> Double {
            var hits = 0
            for k in 0..<side {
                let i: Int
                switch edge {
                case .left: i = k * side
                case .right: i = k * side + side - 1
                case .top: i = k
                case .bottom: i = (side - 1) * side + k
                }
                if warm[i] { hits += 1 }
            }
            return Double(hits) / Double(side)
        }
        let covered = Edge.allCases.filter { coverage($0) >= 0.5 }
        // One side, or a corner. Opposite sides, or three or more, are a scene, not a finger.
        guard !covered.isEmpty, covered.count <= 2 else { return 0 }
        if covered.count == 2 {
            let pair = Set(covered)
            if pair == [.left, .right] || pair == [.top, .bottom] { return 0 }
        }

        let band = side / 3
        func regionShare(_ edge: Edge) -> Double {
            var count = 0, hits = 0
            for y in 0..<side {
                for x in 0..<side {
                    let inside: Bool
                    switch edge {
                    case .left: inside = x < band
                    case .right: inside = x >= side - band
                    case .top: inside = y < band
                    case .bottom: inside = y >= side - band
                    }
                    if inside { count += 1; if warm[y * side + x] { hits += 1 } }
                }
            }
            return count > 0 ? Double(hits) / Double(count) : 0
        }
        let best = covered.filter { $0 != .top }.map(regionShare).max() ?? 0
        return UInt8(min(255, (best * 255).rounded()))
    }
}
