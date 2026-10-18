import Foundation

/// A stretch of a video, in seconds from the start.
nonisolated struct TrimRange: Sendable, Equatable, Hashable {
    let start: Double
    let end: Double
    var duration: Double { max(end - start, 0) }
}

/// One sampled frame of a video: when it is and how it looks.
nonisolated struct TrimSample: Sendable, Equatable {
    let time: Double
    let stats: ExposureStats
}

/// A video with dead stretches (bonus: Smart Trim).
nonisolated struct TrimCandidate: Identifiable, Hashable, Sendable {
    var item: MediaItem
    /// The dead stretches, sorted, never overlapping.
    let deadRanges: [TrimRange]
    /// Compressed bytes inside the dead stretches, measured from the file. Black frames
    /// compress to almost nothing, so time alone overstates the saving.
    var deadBytes: Int64? = nil
    var id: String { item.id }

    var duration: Double { item.duration ?? 0 }
    var deadSeconds: Double { deadRanges.reduce(0) { $0 + $1.duration } }
    var keptSeconds: Double { max(duration - deadSeconds, 0) }
    /// Nothing worth keeping: the whole clip is dark or blank. Offered for removal, not trimming.
    var isAllDead: Bool { keptSeconds < SmartTrimEngine.minimumKept }
    /// The parts a trimmed copy keeps.
    var keptRanges: [TrimRange] { SmartTrimEngine.complement(of: deadRanges, duration: duration) }
    /// The saving: the bytes measured in the dead stretches, or, if they couldn't be
    /// measured, the size in proportion to the time removed.
    var estimatedSaving: Int64 {
        guard duration > 0, let bytes = item.byteSize else { return 0 }
        if isAllDead { return bytes }
        if let deadBytes { return min(deadBytes, bytes) }
        return Int64(Double(bytes) * deadSeconds / duration)
    }

    /// Worth offering: a clip with nothing in it, or a trim that frees at least 1 MB.
    var isWorthOffering: Bool { isAllDead || estimatedSaving >= SmartTrimEngine.minimumSavingBytes }
}

/// Finds the dead stretches of a video from sampled frames. Pure and deterministic,
/// unit-tested in `SmartTrimTests`.
///
/// A frame is dead when it's nearly black with no bright point (recording in a pocket, or
/// face down on a table) or one flat colour (lens covered, pointed at a ceiling). Only
/// stretches long enough to matter are cut: 5 s at either end, 10 s in the middle, so a
/// brief dark moment in a real clip (a tunnel, lights off at a party) is never cut.
/// Frozen but well-lit frames are left alone: a filmed lecture or a sleeping baby barely
/// changes and must not be trimmed.
nonisolated enum SmartTrimEngine {
    /// Videos shorter than this aren't checked.
    static let minimumDuration: Double = 15
    static let minimumEdgeSegment: Double = 5
    static let minimumMiddleSegment: Double = 10
    /// A trimmed copy must save at least this much time and share of the clip.
    static let minimumDeadSeconds: Double = 5
    static let minimumDeadShare: Double = 0.1
    /// A trim must free at least this much to be offered.
    static let minimumSavingBytes: Int64 = 1_000_000
    /// Less kept than this and the clip is "all dead".
    static let minimumKept: Double = 1
    /// At most this many frames are sampled per video.
    static let maximumSamples = 600

    static func isDead(_ stats: ExposureStats) -> Bool {
        (stats.p98 < AccidentalShotEngine.darkP98 && stats.maximum < AccidentalShotEngine.darkMaximum)
            || stats.standardDeviation < 5
    }

    /// Sample times for a video: about one a second, capped at `maximumSamples`.
    static func sampleTimes(duration: Double) -> [Double] {
        guard duration > 0 else { return [] }
        let step = max(1, duration / Double(maximumSamples))
        return stride(from: step / 2, to: duration, by: step).map { $0 }
    }

    /// Dead stretches worth cutting, or [] if the video should be left alone.
    static func deadRanges(samples: [TrimSample], duration: Double) -> [TrimRange] {
        guard duration >= minimumDuration, !samples.isEmpty else { return [] }
        let sorted = samples.sorted { $0.time < $1.time }
        // Each sample stands for the time halfway to its neighbours.
        var runs: [TrimRange] = []
        var runStart: Double?
        for (index, sample) in sorted.enumerated() {
            let from = index == 0 ? 0 : (sorted[index - 1].time + sample.time) / 2
            let to = index == sorted.count - 1 ? duration : (sample.time + sorted[index + 1].time) / 2
            if isDead(sample.stats) {
                if runStart == nil { runStart = from }
                if index == sorted.count - 1, let start = runStart { runs.append(TrimRange(start: start, end: to)) }
            } else if let start = runStart {
                runs.append(TrimRange(start: start, end: from))
                runStart = nil
            }
        }
        let kept = runs.filter { run in
            let touchesEdge = run.start <= 0.01 || run.end >= duration - 0.01
            return run.duration >= (touchesEdge ? minimumEdgeSegment : minimumMiddleSegment)
        }
        let dead = kept.reduce(0) { $0 + $1.duration }
        guard dead >= minimumDeadSeconds, dead / duration >= minimumDeadShare else { return [] }
        return kept
    }

    /// The parts of `0...duration` not covered by `ranges` (sorted, non-overlapping).
    static func complement(of ranges: [TrimRange], duration: Double) -> [TrimRange] {
        var parts: [TrimRange] = []
        var cursor = 0.0
        for range in ranges.sorted(by: { $0.start < $1.start }) {
            if range.start > cursor { parts.append(TrimRange(start: cursor, end: range.start)) }
            cursor = max(cursor, range.end)
        }
        if cursor < duration { parts.append(TrimRange(start: cursor, end: duration)) }
        return parts.filter { $0.duration > 0.05 }
    }
}
