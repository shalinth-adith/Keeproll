import Foundation

/// What the app shares with the Home Screen widget through the App Group. The widget
/// measures free space itself; it only needs the numbers that come from a scan.
nonisolated struct WidgetSnapshot: Codable, Sendable, Equatable {
    var freeableBytes: Int64?
    var lifetimeFreedBytes: Int64 = 0
    var updatedAt: Date?

    static let appGroup = "group.me.adithyan.shalinth.Sift"
    private static let key = "widgetSnapshot"

    static func load() -> WidgetSnapshot {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return snapshot
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }
}
