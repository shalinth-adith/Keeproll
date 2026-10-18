import Foundation
import Observation

/// App-wide selection of everything the user intends to remove. The Review screen reads
/// this, and it's the only source a `CleanupPlan` is built from (D10).
@Observable
final class CleanupCart {
    private(set) var items: [String: CartItem] = [:]

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }
    var totalBytes: Int64 { items.values.reduce(0) { $0 + $1.bytes } }

    func contains(assetID: String) -> Bool { items["asset:\(assetID)"] != nil }
    func contains(contactID: String) -> Bool { items["contact:\(contactID)"] != nil }
    func containsMerge(groupID: UUID) -> Bool { items["merge:\(groupID.uuidString)"] != nil }
    func contains(_ item: CartItem) -> Bool { items[item.key] != nil }

    func toggle(_ item: CartItem) {
        if items[item.key] == nil { items[item.key] = item } else { items[item.key] = nil }
    }

    func add(_ newItems: some Sequence<CartItem>) {
        for item in newItems { items[item.key] = item }
    }

    func remove(_ item: CartItem) { items[item.key] = nil }
    func remove(key: String) { items[key] = nil }

    func removeAssets(_ ids: some Sequence<String>) {
        for id in ids { items["asset:\(id)"] = nil }
    }

    func removeAll(in category: CleanupCategory) {
        items = items.filter { $0.value.category != category }
    }

    /// Drops contact changes that no longer match the latest scan: a merge whose group
    /// changed or vanished, or a delete for a contact that's no longer a duplicate.
    /// Stops a stale merge and a fresh delete from removing both copies of a person (QA H4).
    func pruneContacts(to groups: [DuplicateContactGroup]) {
        let membersByGroup = Dictionary(groups.map { ($0.id, Set($0.contacts.map(\.id))) }, uniquingKeysWith: { a, _ in a })
        let duplicateIDs = Set(groups.flatMap { $0.contacts.map(\.id) })
        let before = items.count
        items = items.filter { _, item in
            switch item {
            case .contactMerge(let groupID, let primaryID, let mergedIDs, _):
                guard let members = membersByGroup[groupID] else { return false }
                return members == Set([primaryID] + mergedIDs)
            case .contactDelete(let id, _):
                return duplicateIDs.contains(id)
            case .asset, .calendarEvent:
                return true
            }
        }
        if items.count != before { Log.cleanup.debug("Pruned \(before - self.items.count) stale contact changes") }
    }

    /// Drops queued event removals that the latest calendar scan no longer suggests. If
    /// the copy you kept was deleted elsewhere, the queued "extra" copy is now the only
    /// one and must not be removed.
    func pruneCalendar(to findings: CalendarFindings?) {
        let suggested = Set((findings?.extraCopies ?? []).map(\.id) + (findings?.oldEvents ?? []).map(\.id))
        let before = items.count
        items = items.filter { _, item in
            if case .calendarEvent(let id, _, _) = item { return suggested.contains(id) }
            return true
        }
        if items.count != before { Log.cleanup.debug("Pruned \(before - self.items.count) stale calendar changes") }
    }

    func items(in category: CleanupCategory) -> [CartItem] {
        items.values.filter { $0.category == category }
    }

    func bytes(in category: CleanupCategory) -> Int64 {
        items(in: category).reduce(0) { $0 + $1.bytes }
    }

    func count(in category: CleanupCategory) -> Int {
        items(in: category).count
    }
}

extension MediaItem {
    func cartItem(in category: CleanupCategory) -> CartItem {
        .asset(id: id, category: category, bytes: byteSize ?? 0)
    }
}
