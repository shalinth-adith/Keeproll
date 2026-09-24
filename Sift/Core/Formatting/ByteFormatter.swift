import Foundation

nonisolated enum ByteFormatter {
    /// "1.4 GB" style, matching how the Settings app counts file sizes.
    static func string(_ bytes: Int64) -> String {
        guard bytes > 0 else {
            // The system formatter spells zero out as "Zero KB" (test report F8).
            let zero = ByteCountFormatter()
            zero.countStyle = .file
            zero.allowedUnits = .useMB
            zero.allowsNonnumericFormatting = false
            return zero.string(fromByteCount: 0)
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

nonisolated enum DurationFormatter {
    /// "0:42", "12:05", "1:02:10".
    static func string(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
