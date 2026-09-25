import EventKit
import Foundation

/// DEBUG-only calendar fixtures for the simulator (see CLAUDE.md §2).
#if DEBUG
extension CalendarService {
    /// `-KeeprollSeedCalendar` launch argument (simulator only in practice): adds fixture events
    /// once, so the Calendar screen can be checked without a real calendar. Expected: 2
    /// duplicate groups (3 extra copies) and 3 old events.
    static func seedFixturesIfRequested(in store: EKEventStore) {
        let key = "debug.calendarSeeded"
        guard ProcessInfo.processInfo.arguments.contains("-KeeprollSeedCalendar"),
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
