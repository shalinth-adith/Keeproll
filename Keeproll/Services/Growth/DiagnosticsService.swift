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
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try data.write(to: directory.appendingPathComponent("\(kind)-\(stamp).json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            prune()
            Log.ui.debug("Stored a MetricKit \(kind, privacy: .public) payload")
        } catch {
            Log.ui.error("MetricKit payload not stored: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Newest first.
    nonisolated static func reports() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Keep the last 30 files; a month is enough context for any bug report.
    private nonisolated static func prune() {
        for url in reports().dropFirst(30) { try? FileManager.default.removeItem(at: url) }
    }
}
