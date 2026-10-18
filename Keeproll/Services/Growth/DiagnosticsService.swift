import Foundation
import MetricKit

/// Crash, hang and performance reports from the system, kept on this iPhone.
///
/// MetricKit hands the app a daily payload (and crash diagnostics on the next launch)
/// only when the person has agreed to share analytics with developers in iOS Settings.
/// Nothing here goes anywhere: payloads are written as JSON under Application Support
/// so a user who hits a problem can attach the latest file from Settings → Diagnostics.
/// No SDK, no network, consistent with the privacy policy.
final class DiagnosticsService: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsService()

    nonisolated static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Diagnostics")
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads { Self.write(payload.jsonRepresentation(), kind: "metrics") }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads { Self.write(payload.jsonRepresentation(), kind: "diagnostic") }
    }

    private nonisolated static func write(_ data: Data, kind: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(fileName(kind: kind)), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            prune()
            Log.ui.debug("Stored a MetricKit \(kind, privacy: .public) payload")
        } catch {
            Log.ui.error("MetricKit payload not stored: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A unique name: two payloads in the same second used to overwrite each other (QA L11).
    nonisolated static func fileName(kind: String, date: Date = Date(), unique: UUID = UUID()) -> String {
        let stamp = ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")
        return "\(kind)-\(stamp)-\(unique.uuidString.prefix(8).lowercased()).json"
    }

    /// Newest first (by file date, so metrics and diagnostics interleave correctly).
    nonisolated static func reports() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        func date(_ url: URL) -> Date { (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        return urls.filter { $0.pathExtension == "json" }.sorted { date($0) > date($1) }
    }

    /// Keep the last 30 files; a month is enough context for any bug report.
    private nonisolated static func prune() {
        for url in reports().dropFirst(30) { try? FileManager.default.removeItem(at: url) }
    }
}
