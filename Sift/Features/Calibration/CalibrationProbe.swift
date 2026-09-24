#if DEBUG
import Foundation

/// What a DEBUG scan learned about this library, for tuning `SimilarityConfig`.
/// Holds asset ids so the calibration screen can show the photos on the device;
/// only aggregate numbers are ever logged.
nonisolated struct CalibrationData: Sendable {
    nonisolated struct Pair: Sendable, Hashable {
        let a: String
        let b: String
        let featureDistance: Float?
        let hashDistance: Int
        let seconds: TimeInterval
    }

    let photos: Int
    let seconds: TimeInterval
    let comparisons: Int
    let comparisonsWithPrints: Int
    /// Count of time-window comparisons per 0.05-wide feature-distance bin.
    let histogram: [Int]
    /// A few example pairs from every bin, for labelling.
    let samples: [Pair]
    /// Every photo's sharpness score, ascending.
    let sharpness: [(id: String, value: Float)]
    let groupSizes: [Int]

    static let binWidth: Float = 0.05
    static let binCount = 30 // 0 … 1.5
}

/// Collects comparison statistics during a scan (one scan task, never shared).
nonisolated final class CalibrationProbe {
    private var histogram = [Int](repeating: 0, count: CalibrationData.binCount)
    private var perBin: [[CalibrationData.Pair]] = Array(repeating: [], count: CalibrationData.binCount)
    private var hashOnly: [CalibrationData.Pair] = []
    private var comparisons = 0
    private var withPrints = 0
    private let samplesPerBin = 6

    func record(a: String, b: String, featureDistance: Float?, hashDistance: Int, seconds: TimeInterval) {
        comparisons += 1
        let pair = CalibrationData.Pair(a: a, b: b, featureDistance: featureDistance, hashDistance: hashDistance, seconds: seconds)
        guard let distance = featureDistance else {
            if hashOnly.count < 40 { hashOnly.append(pair) }
            return
        }
        withPrints += 1
        let bin = min(Int(distance / CalibrationData.binWidth), CalibrationData.binCount - 1)
        histogram[bin] += 1
        // Reservoir sampling keeps an unbiased handful per bin on any library size.
        if perBin[bin].count < samplesPerBin {
            perBin[bin].append(pair)
        } else if Int.random(in: 0..<histogram[bin]) < samplesPerBin {
            perBin[bin][Int.random(in: 0..<samplesPerBin)] = pair
        }
    }

    func finish(sharpness: [String: Float], groups: [[String]], photos: Int, seconds: TimeInterval) -> CalibrationData {
        let data = CalibrationData(
            photos: photos, seconds: seconds, comparisons: comparisons, comparisonsWithPrints: withPrints,
            histogram: histogram, samples: perBin.flatMap { $0 } + hashOnly,
            sharpness: sharpness.map { ($0.key, $0.value) }.sorted { $0.value < $1.value },
            groupSizes: groups.map(\.count)
        )
        CalibrationReport.log(data)
        return data
    }
}

/// Numbers-only console output (read with `devicectl … --console`). Never ids or names.
nonisolated enum CalibrationReport {
    static func log(_ d: CalibrationData) {
        var lines = ["[calibration] photos=\(d.photos) seconds=\(String(format: "%.2f", d.seconds)) comparisons=\(d.comparisons) withPrints=\(d.comparisonsWithPrints) groups=\(d.groupSizes.count) groupedPhotos=\(d.groupSizes.reduce(0, +)) largestGroup=\(d.groupSizes.max() ?? 0)"]
        let bins = d.histogram.enumerated().filter { $0.element > 0 }
            .map { String(format: "%.2f:%d", Float($0.offset) * CalibrationData.binWidth, $0.element) }
        lines.append("[calibration] featureDistanceHistogram " + bins.joined(separator: " "))
        let values = d.sharpness.map(\.value)
        if !values.isEmpty {
            let pct = [1, 5, 10, 25, 50, 75, 90].map { p in
                String(format: "p%d=%.0f", p, values[min(values.count - 1, values.count * p / 100)])
            }
            lines.append("[calibration] sharpness " + pct.joined(separator: " "))
        }
        lines.forEach { print($0) }
    }

    static func logLabels(kind: String, _ rows: [(threshold: Float, precision: Double, recall: Double, n: Int)], recommended: Float?) {
        let table = rows.map { String(format: "t=%.2f p=%.2f r=%.2f n=%d", $0.threshold, $0.precision, $0.recall, $0.n) }
        print("[calibration] \(kind) labels: " + table.joined(separator: " | "))
        print("[calibration] \(kind) recommended=\(recommended.map { String(format: "%.2f", $0) } ?? "none")")
    }
}
#endif
