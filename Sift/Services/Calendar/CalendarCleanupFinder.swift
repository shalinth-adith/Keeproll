import Foundation

/// One calendar event, as a Sendable value (never an `EKEvent`).
nonisolated struct CalendarEventSummary: Identifiable, Hashable, Sendable {
    /// `EKEvent.eventIdentifier`.
    let id: String
    let title: String
    let start: Date?
    let end: Date?
    let calendarTitle: String
    let isAllDay: Bool
}

/// What calendar cleanup suggests. Only single (non-repeating) events in calendars the
/// user can edit are ever included; the scanner filters the rest out.
nonisolated struct CalendarFindings: Hashable, Sendable {
    /// Identical events (same title, start and end). The first of each group is kept.
    var duplicateGroups: [[CalendarEventSummary]] = []
    /// Events that ended more than a year ago, newest first.
    var oldEvents: [CalendarEventSummary] = []

    var extraCopies: [CalendarEventSummary] { duplicateGroups.flatMap { $0.dropFirst() } }
    var suggestionCount: Int { extraCopies.count + oldEvents.count }
    var isEmpty: Bool { suggestionCount == 0 }

    func removing(_ ids: Set<String>) -> CalendarFindings {
        CalendarFindings(
            duplicateGroups: duplicateGroups.map { $0.filter { !ids.contains($0.id) } }.filter { $0.count > 1 },
            oldEvents: oldEvents.filter { !ids.contains($0.id) }
        )
    }
}

/// Pure logic for calendar cleanup (unit-tested without EventKit).
nonisolated enum CalendarCleanupFinder {
    static let oldAfter: TimeInterval = 365 * 24 * 60 * 60

    static func find(_ events: [CalendarEventSummary], now: Date = Date()) -> CalendarFindings {
        // Duplicates: same title (case/space-insensitive), same start and end, same all-day flag.
        var buckets: [String: [CalendarEventSummary]] = [:]
        for event in events {
            guard let start = event.start else { continue }
            let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !title.isEmpty else { continue }
            let key = "\(title)|\(start.timeIntervalSinceReferenceDate)|\(event.end?.timeIntervalSinceReferenceDate ?? 0)|\(event.isAllDay)"
            buckets[key, default: []].append(event)
        }
        let groups = buckets.values
            .filter { $0.count > 1 }
            .map { $0.sorted { $0.id < $1.id } }
            .sorted { ($0[0].start ?? .distantPast) > ($1[0].start ?? .distantPast) }
        let inDuplicates = Set(groups.flatMap { $0.map(\.id) })

        let cutoff = now.addingTimeInterval(-oldAfter)
        let old = events
            .filter { !inDuplicates.contains($0.id) && ($0.end ?? $0.start ?? .distantFuture) < cutoff }
            .sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }

        return CalendarFindings(duplicateGroups: groups, oldEvents: old)
    }
}

/// Minimal iCalendar (RFC 5545) writer for the pre-delete backup. Opening the file in
/// Calendar brings the events back.
nonisolated enum ICSWriter {
    nonisolated struct Event: Sendable {
        var uid: String
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        var location: String?
        var notes: String?
        var url: String?
    }

    static func document(_ events: [Event], now: Date = Date()) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Sift//Calendar backup//EN", "CALSCALE:GREGORIAN"]
        for e in events {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:" + escape(e.uid))
            lines.append("DTSTAMP:" + utc(now))
            if e.isAllDay {
                lines.append("DTSTART;VALUE=DATE:" + day(e.start))
                lines.append("DTEND;VALUE=DATE:" + day(e.end))
            } else {
                lines.append("DTSTART:" + utc(e.start))
                lines.append("DTEND:" + utc(e.end))
            }
            lines.append("SUMMARY:" + escape(e.title))
            if let v = e.location, !v.isEmpty { lines.append("LOCATION:" + escape(v)) }
            if let v = e.notes, !v.isEmpty { lines.append("DESCRIPTION:" + escape(v)) }
            if let v = e.url, !v.isEmpty { lines.append("URL:" + v) }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Lines longer than 75 octets are folded with CRLF + space (RFC 5545 §3.1).
    static func fold(_ line: String) -> String {
        var out = ""
        var count = 0
        for ch in line {
            let size = String(ch).utf8.count
            if count + size > 75 {
                out += "\r\n "
                count = 1
            }
            out.append(ch)
            count += size
        }
        return out
    }

    private static func utc(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    private static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }
}
