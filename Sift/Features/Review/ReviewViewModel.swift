import Foundation
import Observation

/// An approved list of things to delete or merge.
///
/// The initialiser is `fileprivate`, so the only code that can build a plan is
/// `ReviewViewModel.confirm()` in this file. That makes "nothing is deleted without
/// approval on the Review screen" a compile-time guarantee (D10).
nonisolated struct CleanupPlan: Sendable {
    nonisolated struct Item: Hashable, Sendable {
        let key: String
        let assetID: String
        let category: CleanupCategory
        let bytes: Int64
    }

    nonisolated enum ContactAction: Hashable, Sendable {
        case merge(key: String, primaryID: String, mergedIDs: [String])
        case delete(key: String, id: String)

        var key: String {
            switch self {
            case .merge(let key, _, _), .delete(let key, _): key
            }
        }

        /// Every contact this action touches (for the backup).
        var affectedIDs: [String] {
            switch self {
            case .merge(_, let primary, let merged): [primary] + merged
            case .delete(_, let id): [id]
            }
        }
    }

    nonisolated struct CalendarEvent: Hashable, Sendable {
        let key: String
        let id: String
    }

    let items: [Item]
    let contactActions: [ContactAction]
    let calendarEvents: [CalendarEvent]

    var assetIDs: [String] { items.map(\.assetID) }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    var isEmpty: Bool { items.isEmpty && contactActions.isEmpty && calendarEvents.isEmpty }

    fileprivate init(cartItems: [CartItem]) {
        var items: [Item] = []
        var actions: [ContactAction] = []
        var events: [CalendarEvent] = []
        for item in cartItems {
            switch item {
            case .asset(let id, let category, let bytes):
                items.append(Item(key: item.key, assetID: id, category: category, bytes: bytes))
            case .contactMerge(_, let primaryID, let mergedIDs, _):
                actions.append(.merge(key: item.key, primaryID: primaryID, mergedIDs: mergedIDs))
            case .contactDelete(let id, _):
                actions.append(.delete(key: item.key, id: id))
            case .calendarEvent(let id, _, _):
                events.append(CalendarEvent(key: item.key, id: id))
            }
        }
        self.items = items
        self.contactActions = actions
        self.calendarEvents = events
    }
}

@Observable
final class ReviewViewModel {
    enum Phase: Equatable {
        case reviewing
        case deleting
        case finished(CleanupResult)
    }

    private(set) var phase: Phase = .reviewing

    let cart: CleanupCart
    private let deletion: DeletionServicing
    private let scanStore: ScanStore
    private let settings: SettingsStore

    init(cart: CleanupCart, deletion: DeletionServicing, scanStore: ScanStore, settings: SettingsStore) {
        self.cart = cart
        self.deletion = deletion
        self.scanStore = scanStore
        self.settings = settings
    }

    /// Categories that have something in the cart, in dashboard order.
    var sections: [CleanupCategory] {
        CleanupCategory.allCases.filter { cart.count(in: $0) > 0 }
    }

    var mediaCount: Int { cart.items.values.filter { if case .asset = $0 { true } else { false } }.count }
    var contactActionCount: Int { cart.count(in: .contacts) }
    var calendarEventCount: Int { cart.count(in: .calendar) }
    /// Contact and calendar changes: things with no byte size.
    var recordChangeCount: Int { contactActionCount + calendarEventCount }

    func assetIDs(in category: CleanupCategory) -> [String] {
        cart.items(in: category).compactMap {
            if case .asset(let id, _, _) = $0 { id } else { nil }
        }.sorted()
    }

    /// Rows for record categories (contacts: merges first; calendar: oldest first).
    func recordItems(in category: CleanupCategory) -> [CartItem] {
        cart.items(in: category).sorted { a, b in
            switch (a, b) {
            case (.contactMerge, .contactDelete): return true
            case (.contactDelete, .contactMerge): return false
            case (.calendarEvent(_, _, let da), .calendarEvent(_, _, let db)):
                return (da ?? .distantPast) < (db ?? .distantPast)
            default: return a.key < b.key
            }
        }
    }

    /// Selected items whose original is only in iCloud, and their bytes. Removing them
    /// frees iCloud space, not iPhone storage (FR-SIM-7).
    var cloudOnly: (count: Int, bytes: Int64) {
        let ids = scanStore.cloudOnlyIDs
        return cart.items.values.reduce(into: (0, Int64(0))) { total, item in
            if case .asset(let id, _, let bytes) = item, ids.contains(id) {
                total.0 += 1
                total.1 += bytes
            }
        }
    }

    func remove(assetID: String) { cart.removeAssets([assetID]) }
    func remove(_ item: CartItem) { cart.remove(item) }

    /// The user tapped the Delete button. Builds the plan from the cart and runs it.
    func confirm() async {
        guard !cart.isEmpty, phase == .reviewing else { return }
        let plan = CleanupPlan(cartItems: Array(cart.items.values))
        Log.cleanup.debug("Review confirmed: \(plan.items.count) assets, \(plan.contactActions.count) contact actions, \(plan.totalBytes) bytes")
        phase = .deleting
        // The iOS delete prompt backgrounds the app, and the delete itself posts library
        // changes: neither should trigger a rescan.
        scanStore.expectOwnChanges()
        let result = await deletion.execute(plan)

        if result.wasCancelled {
            // Nothing deleted; keep the cart exactly as it was (FR-REV-5).
            phase = .reviewing
            return
        }
        let deleted = Set(result.deletedAssetIDs)
        cart.removeAssets(deleted)
        scanStore.removeAssets(deleted)

        let failedKeys = Set(result.failures.map(\.itemKey))
        let doneActions = plan.contactActions.filter { !failedKeys.contains($0.key) }
        for action in doneActions { cart.remove(key: action.key) }
        let goneContacts = Set(doneActions.flatMap { action -> [String] in
            switch action {
            case .merge(_, _, let merged): merged
            case .delete(_, let id): [id]
            }
        })
        scanStore.removeContacts(goneContacts)

        let doneEvents = plan.calendarEvents.filter { !failedKeys.contains($0.key) }
        for event in doneEvents { cart.remove(key: event.key) }
        scanStore.removeCalendarEvents(Set(doneEvents.map(\.id)))

        settings.recordFreed(result.bytesFreed)
        phase = .finished(result)
    }
}
