import CoreGraphics
import Foundation

/// Brightness and colour statistics of a photo (bonus: Accidental Shots), from the
/// thumbnail the similarity scan already loads. Seven bytes per photo, cached.
///
/// Brightness is measured at the thumbnail's own size (up to 256 px), so small bright
/// points such as stars or distant lights survive; shrinking first averaged them away
/// (QA A2). Colour and the finger check use a 96 × 96 render.
nonisolated struct ExposureStats: Sendable, Equatable {
    /// Luma, 0–255.
    let mean: UInt8
    let standardDeviation: UInt8
    /// 98th percentile luma: a pocket shot has almost nothing bright in it.
    let p98: UInt8
    /// Brightest 2 × 2 block (a lone hot pixel doesn't count).
    let maximum: UInt8
    /// Pixels brighter than `litLevel`, per 10,000, capped at 255. Stars, the moon and
    /// city lights make this well above zero; a pocket shot leaves it at zero.
    let litPerTenThousand: UInt8
    /// Mean colourfulness (max − min of R, G, B), 0–255. Near zero for grey or white.
    let saturation: UInt8
    /// 0–255: how much of one edge band is a soft, warm, skin-lit blob (a finger over
    /// the lens). 0 unless the blob's edge is out of focus.
    let fingerScore: UInt8

    /// Side of the colour render used for saturation and the finger check.
    static let colourSide = 96
    /// Brightness measurement cap.
    static let lumaSide = 256
    static let litLevel: UInt8 = 80

    init(mean: UInt8, standardDeviation: UInt8, p98: UInt8, maximum: UInt8,
         litPerTenThousand: UInt8 = 0, saturation: UInt8 = 0, fingerScore: UInt8 = 0) {
        self.mean = mean
        self.standardDeviation = standardDeviation
        self.p98 = p98
        self.maximum = maximum
        self.litPerTenThousand = litPerTenThousand
        self.saturation = saturation
        self.fingerScore = fingerScore
    }
}

/// Why a photo looks like it was taken by accident.
nonisolated enum AccidentalReason: String, CaseIterable, Hashable, Sendable {
    /// Almost black: taken in a pocket or bag, or face down.
    case tooDark
    /// A finger covering part of the lens.
    case finger
    /// One flat grey with no detail: a ceiling, a wall, the inside of a case.
    case blank
}

/// A photo flagged as an accidental shot.
nonisolated struct AccidentalShot: Identifiable, Hashable, Sendable {
    var item: MediaItem
    let reason: AccidentalReason
    var id: String { item.id }
}

/// Decides whether a photo is an accidental shot. Pure and deterministic, unit-tested in
/// `AccidentalShotTests`. Deliberately conservative: a real night photo, a clear sky, a
/// colour swatch or a portrait in a red top must never be flagged, so every rule needs a
/// strong signal.
nonisolated enum AccidentalShotEngine {
    /// p98 below this, with no bright point and (almost) no lit pixels, is a pocket shot.
    static let darkP98: UInt8 = 40
    static let darkMaximum: UInt8 = 100
    static let darkMaxLit: UInt8 = 2 // 0.02 % of the frame
    /// A frame flatter than this is one colour (a gradient sky is well above it).
    static let blankDeviation: UInt8 = 6
    static let blankSharpness: Float = 0.12
    /// Blank also needs to be grey: a paint swatch or a coloured wall is deliberate (QA A4).
    static let blankMaxSaturation: UInt8 = 20
    /// Share of the edge band a finger must cover.
    static let fingerThreshold: UInt8 = 115 // ≈ 45 %
    /// A finger's edge is far out of focus. The median Laplacian along the blob's edge
    /// must stay below this; a shirt or a car door has a crisp edge (QA A1).
    static let fingerEdgeSoftness = 12

    static func verdict(stats: ExposureStats, sharpness: Float, isFavorite: Bool) -> AccidentalReason? {
        if isFavorite { return nil }
        if isDark(stats) { return .tooDark }
        if stats.fingerScore >= fingerThreshold { return .finger }
        if stats.standardDeviation < blankDeviation && sharpness < blankSharpness
            && stats.saturation < blankMaxSaturation && stats.p98 &- stats.mean < 12 { return .blank }
        return nil
    }

    /// Nearly black, with no bright point and no scattered lights (stars, city lights).
    static func isDark(_ stats: ExposureStats) -> Bool {
        stats.p98 < darkP98 && stats.maximum < darkMaximum && stats.litPerTenThousand <= darkMaxLit
    }

    // MARK: - Statistics

    /// Measures `image`. Brightness at up to 256 px, colour and finger at 96 px.
    static func stats(_ image: CGImage) -> ExposureStats? {
        let longEdge = max(image.width, image.height)
        let scale = min(1, Double(ExposureStats.lumaSide) / Double(max(longEdge, 1)))
        let width = max(4, Int(Double(image.width) * scale)), height = max(4, Int(Double(image.height) * scale))
        guard let luma = ImageAnalysis.grayscale(image, width: width, height: height),
              let rgba = render(image, side: ExposureStats.colourSide) else { return nil }
        return stats(luma: luma, width: width, height: height, rgba: rgba, side: ExposureStats.colourSide)
    }

    private static func render(_ image: CGImage, side: Int) -> [UInt8]? {
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
        return drawn ? pixels : nil
    }

    /// Statistics from a luma buffer (any size) and a square RGBA buffer.
    static func stats(luma: [UInt8], width: Int, height: Int, rgba: [UInt8], side: Int) -> ExposureStats? {
        let count = width * height
        guard width >= 2, height >= 2, luma.count >= count, side >= 4, rgba.count >= side * side * 4 else { return nil }
        var histogram = [Int](repeating: 0, count: 256)
        var sum = 0.0, sumSquares = 0.0
        var lit = 0
        for i in 0..<count {
            let y = luma[i]
            histogram[Int(y)] += 1
            sum += Double(y)
            sumSquares += Double(y) * Double(y)
            if y > ExposureStats.litLevel { lit += 1 }
        }
        // Brightest 2 × 2 block, so one hot pixel in a pocket shot doesn't count as light.
        var maximum = 0
        for y in 0..<(height - 1) {
            for x in 0..<(width - 1) {
                let i = y * width + x
                let block = (Int(luma[i]) + Int(luma[i + 1]) + Int(luma[i + width]) + Int(luma[i + width + 1])) / 4
                maximum = max(maximum, block)
            }
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
        var chroma = 0
        for i in 0..<(side * side) {
            let r = Int(rgba[i * 4]), g = Int(rgba[i * 4 + 1]), b = Int(rgba[i * 4 + 2])
            chroma += max(r, g, b) - min(r, g, b)
        }
        return ExposureStats(
            mean: UInt8(mean.rounded()), standardDeviation: UInt8(min(255, deviation.rounded())),
            p98: p98, maximum: UInt8(maximum),
            litPerTenThousand: UInt8(min(255, lit * 10_000 / max(count, 1))),
            saturation: UInt8(min(255, chroma / (side * side))),
            fingerScore: fingerScore(rgba: rgba, side: side)
        )
    }

    /// Convenience for square RGBA buffers (tests and video frames): luma comes from the
    /// same pixels.
    static func stats(rgba: [UInt8], side: Int) -> ExposureStats? {
        guard rgba.count >= side * side * 4 else { return nil }
        let luma = (0..<(side * side)).map { i in luma(rgba, i) }
        return stats(luma: luma, width: side, height: side, rgba: rgba, side: side)
    }

    private static func luma(_ rgba: [UInt8], _ i: Int) -> UInt8 {
        let r = Double(rgba[i * 4]), g = Double(rgba[i * 4 + 1]), b = Double(rgba[i * 4 + 2])
        return UInt8(min(255, max(0, (0.299 * r + 0.587 * g + 0.114 * b).rounded())))
    }

    /// A finger over the lens is a soft, out-of-focus, skin-lit (red to orange) blob that
    /// comes in from one side or one corner. Returns how much of the third of the frame
    /// next to that side it covers, scaled to 0–255.
    ///
    /// What rules out look-alikes:
    /// - **Focus.** The blob's edge must be soft: a finger right against the lens is
    ///   completely out of focus, while clothing, car doors and walls have crisp edges.
    /// - **Shape.** Only one edge, or two adjacent edges (a corner), may be mostly warm. A
    ///   warm background touches every edge; a sunset or a wooden table touches three or four.
    /// - **Colour.** Red must clearly beat green (skin with light through it), which
    ///   excludes sand, wood and beige walls.
    /// - **Side.** The finger's own edge is left, right or bottom, never the top: the top of
    ///   an upright photo is where skies are.
    static func fingerScore(rgba: [UInt8], side: Int) -> UInt8 {
        let n = side * side
        var luma = [Int](repeating: 0, count: n)
        var warm = [Bool](repeating: false, count: n)
        for i in 0..<n {
            luma[i] = Int(Self.luma(rgba, i))
            let r = Int(rgba[i * 4]), g = Int(rgba[i * 4 + 1]), b = Int(rgba[i * 4 + 2])
            warm[i] = r >= 70 && r * 10 >= g * 13 && g + 20 >= b && r - b >= 35
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

        // Focus: the median Laplacian along the blob's inner edge. A soft edge ramps
        // smoothly (Laplacian near 0); a crisp one steps (Laplacian near the contrast).
        var edgeResponses: [Int] = []
        for y in 1..<(side - 1) {
            for x in 1..<(side - 1) {
                let i = y * side + x
                guard warm[i], !warm[i - 1] || !warm[i + 1] || !warm[i - side] || !warm[i + side] else { continue }
                edgeResponses.append(abs(4 * luma[i] - luma[i - 1] - luma[i + 1] - luma[i - side] - luma[i + side]))
            }
        }
        if !edgeResponses.isEmpty {
            edgeResponses.sort()
            if edgeResponses[edgeResponses.count / 2] > fingerEdgeSoftness { return 0 }
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
