import EventKit

nonisolated protocol CalendarScanning: Sendable {
    func findCleanup() async -> CalendarFindings
}

/// Reads calendars and removes approved events.
///
/// Safety: only single events (never repeating ones) in calendars the user can edit
/// (not birthdays, holidays or subscriptions). Removals only arrive through
/// `DeletionService` with a Review-approved plan (D10), and an .ics backup of every
/// affected event is written first, since Calendar has no Recently Deleted.
/// A fresh `EKEventStore` is created per call (it isn't Sendable).
nonisolated final class CalendarService: CalendarScanning, CalendarMutating {
    private let backupDirectory: URL
    /// How far back to look. One EventKit predicate can span at most 4 years, so the
    /// search runs a year at a time.
    private let yearsBack = 6

    init(backupDirectory: URL = ContactsService.defaultBackupDirectory) {
        self.backupDirectory = backupDirectory
    }

    @concurrent
    func findCleanup() async -> CalendarFindings {
        let signpost = Signposts.scan.beginInterval("scan.calendar")
        defer { Signposts.scan.endInterval("scan.calendar", signpost) }
        let store = EKEventStore()
        #if DEBUG
        Self.seedFixturesIfRequested(in: store)
        #endif
        let calendars = Self.editableCalendars(in: store)
        guard !calendars.isEmpty else { return CalendarFindings() }

        let now = Date()
        var seen = Set<String>()
        var events: [CalendarEventSummary] = []
        for year in 0..<yearsBack {
            let end = Calendar.current.date(byAdding: .year, value: -year, to: now) ?? now
            let start = Calendar.current.date(byAdding: .year, value: -1, to: end) ?? end
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
            for event in store.events(matching: predicate) where !event.hasRecurrenceRules {
                guard let id = event.eventIdentifier, seen.insert(id).inserted else { continue }
                events.append(CalendarEventSummary(
                    id: id, title: event.title ?? "", start: event.startDate, end: event.endDate,
                    calendarTitle: event.calendar?.title ?? "", isAllDay: event.isAllDay
                ))
            }
        }
        let findings = CalendarCleanupFinder.find(events, now: now)
        Log.scan.debug("Calendar: \(events.count) single events, \(findings.duplicateGroups.count) duplicate groups, \(findings.oldEvents.count) old")
        return findings
    }

    @concurrent
    func delete(_ events: [CleanupPlan.CalendarEvent]) async -> (backup: URL?, failures: [CleanupFailure]) {
        let store = EKEventStore()
        var found: [(CleanupPlan.CalendarEvent, EKEvent)] = []
        var failures: [CleanupFailure] = []
        for item in events {
            if let event = store.event(withIdentifier: item.id), event.calendar?.allowsContentModifications == true,
               !event.hasRecurrenceRules {
                found.append((item, event))
            } else {
                failures.append(.init(itemKey: item.key, reason: String(localized: "This event no longer exists or can't be changed.")))
            }
        }
        guard !found.isEmpty else { return (nil, failures) }

        // 1. Backup first. If it can't be written, change nothing.
        let backup: URL
        do {
            backup = try writeBackup(found.map(\.1))
        } catch {
            Log.cleanup.error("Calendar backup failed, nothing changed: \(error.localizedDescription, privacy: .public)")
            let reason = String(localized: "Couldn't save a backup first, so nothing was changed.")
            return (nil, failures + found.map { CleanupFailure(itemKey: $0.0.key, reason: reason) })
        }

        // 2. Remove, then commit once.
        var removed: [CleanupPlan.CalendarEvent] = []
        for (item, event) in found {
            do {
                try store.remove(event, span: .thisEvent, commit: false)
                removed.append(item)
            } catch {
                failures.append(.init(itemKey: item.key, reason: String(localized: "This calendar doesn't allow changes.")))
            }
        }
        do {
            try store.commit()
        } catch {
            store.reset()
            let reason = String(localized: "Calendar couldn't save the change.")
            return (backup, failures + removed.map { CleanupFailure(itemKey: $0.key, reason: reason) })
        }
        Log.cleanup.debug("Removed \(removed.count) calendar events after backup")
        return (backup, failures)
    }

    private static func editableCalendars(in store: EKEventStore) -> [EKCalendar] {
        store.calendars(for: .event).filter {
            $0.allowsContentModifications && $0.type != .birthday && $0.type != .subscription
        }
    }

    private func writeBackup(_ events: [EKEvent]) throws -> URL {
        let items = events.compactMap { e -> ICSWriter.Event? in
            guard let start = e.startDate, let end = e.endDate else { return nil }
            return ICSWriter.Event(uid: e.calendarItemExternalIdentifier ?? e.eventIdentifier ?? UUID().uuidString,
                                   title: e.title ?? "", start: start, end: end, isAllDay: e.isAllDay,
                                   location: e.location, notes: e.notes, url: e.url?.absoluteString)
        }
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = backupDirectory.appendingPathComponent("calendar-\(stamp).ics")
        try Data(ICSWriter.document(items).utf8).write(to: url, options: [.atomic, .completeFileProtection])
        Log.cleanup.debug("Backed up \(items.count) events before changes")
        return url
    }
}

#if DEBUG
extension CalendarService {
    /// `-SiftSeedCalendar` launch argument (simulator only in practice): adds fixture events
    /// once, so the Calendar screen can be checked without a real calendar. Expected: 2
    /// duplicate groups (3 extra copies) and 3 old events.
    static func seedFixturesIfRequested(in store: EKEventStore) {
        let key = "debug.calendarSeeded"
        guard ProcessInfo.processInfo.arguments.contains("-SiftSeedCalendar"),
              !UserDefaults.standard.bool(forKey: key),
              let calendar = store.defaultCalendarForNewEvents else { return }
        let day: TimeInterval = 86_400
        let now = Date()
        let fixtures: [(String, TimeInterval, Int)] = [
            ("PLACEHOLDER_Standup", 30, 3), ("PLACEHOLDER_Dentist", 10, 2),
            ("PLACEHOLDER_Conference", 420, 1), ("PLACEHOLDER_Workshop", 800, 1),
            ("PLACEHOLDER_Trip", 1_500, 1), ("PLACEHOLDER_Lunch", 5, 1),
        ]
        for (title, daysAgo, copies) in fixtures {
            let start = Calendar.current.startOfDay(for: now.addingTimeInterval(-daysAgo * day)).addingTimeInterval(10 * 3600)
            for _ in 0..<copies {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                event.title = title
                event.startDate = start
                event.endDate = start.addingTimeInterval(3600)
                try? store.save(event, span: .thisEvent, commit: false)
            }
        }
        try? store.commit()
        UserDefaults.standard.set(true, forKey: key)
    }
}
#endif
