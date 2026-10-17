import Foundation

/// One reading of the device's storage, at most one per calendar day.
nonisolated struct StorageSample: Codable, Sendable, Equatable {
    let date: Date
    let availableBytes: Int64
    let totalBytes: Int64
}

/// What the trend says (bonus: storage forecast on Home). Pure; tested in `StorageForecasterTests`.
nonisolated enum StorageForecast: Sendable, Equatable {
    /// Fewer than `minimumDays` distinct days recorded so far.
    case notEnoughData(daysRecorded: Int)
    /// Free space is shrinking by `perDay`; at this rate it reaches the floor in `daysLeft`.
    case filling(perDay: Int64, daysLeft: Int)
    /// Change is under the noise floor either way.
    case steady
    /// Free space is growing by `perDay` (cleanups outpacing new photos).
    case freeingUp(perDay: Int64)
}

nonisolated enum StorageForecaster {
    /// Days of history needed before a trend is shown.
    static let minimumDays = 3
    /// Longest window the fit uses.
    static let windowDays = 30
    /// Below this iOS itself starts to struggle (updates fail, camera refuses): the "full" line.
    static let floorBytes: Int64 = 2_000_000_000
    /// Daily drift smaller than this (or than 0.01 % of the device: ~50 MB on 512 GB) is "steady".
    static let noiseBytesPerDay: Int64 = 20_000_000

    /// Keeps one sample per day (the latest wins) and trims to the window plus a margin.
    static func appending(_ sample: StorageSample, to history: [StorageSample], calendar: Calendar = .current) -> [StorageSample] {
        var kept = history.filter { !calendar.isDate($0.date, inSameDayAs: sample.date) }
        kept.append(sample)
        kept.sort { $0.date < $1.date }
        let cutoff = sample.date.addingTimeInterval(-Double(windowDays + 5) * 86_400)
        return kept.filter { $0.date >= cutoff }
    }

    static func forecast(_ history: [StorageSample], now: Date = Date()) -> StorageForecast {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let window = history.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        guard let first = window.first, let last = window.last else { return .notEnoughData(daysRecorded: 0) }
        let span = last.date.timeIntervalSince(first.date) / 86_400
        guard window.count >= minimumDays, span >= Double(minimumDays - 1) else {
            return .notEnoughData(daysRecorded: window.count)
        }
        // Least-squares slope of free bytes against days.
        let xs = window.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let ys = window.map { Double($0.availableBytes) }
        let n = Double(window.count)
        let meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (x, y) in zip(xs, ys) { num += (x - meanX) * (y - meanY); den += (x - meanX) * (x - meanX) }
        guard den > 0 else { return .steady }
        let slope = num / den // bytes of free space per day; negative = filling

        let noise = max(Double(noiseBytesPerDay), Double(last.totalBytes) * 0.0001)
        if abs(slope) < noise { return .steady }
        if slope > 0 { return .freeingUp(perDay: Int64(slope)) }
        let headroom = Double(last.availableBytes - floorBytes)
        let days = headroom <= 0 ? 0 : Int((headroom / -slope).rounded())
        return .filling(perDay: Int64(-slope), daysLeft: days)
    }
}
