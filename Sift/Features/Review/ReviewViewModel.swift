import Foundation
import Observation

/// An approved list of things to delete.
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

    let items: [Item]

    var assetIDs: [String] { items.map(\.assetID) }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    fileprivate init(cartItems: [CartItem]) {
        items = cartItems.map { item in
            switch item {
            case .asset(let id, let category, let bytes):
                Item(key: item.key, assetID: id, category: category, bytes: bytes)
            }
        }
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

    func assetIDs(in category: CleanupCategory) -> [String] {
        cart.items(in: category).compactMap {
            if case .asset(let id, _, _) = $0 { id } else { nil }
        }.sorted()
    }

    func remove(assetID: String) {
        cart.removeAssets([assetID])
    }

    /// The user tapped the Delete button. Builds the plan from the cart and runs it.
    func confirm() async {
        guard !cart.isEmpty, phase == .reviewing else { return }
        let plan = CleanupPlan(cartItems: Array(cart.items.values))
        Log.cleanup.debug("Review confirmed: \(plan.items.count) items, \(plan.totalBytes) bytes")
        phase = .deleting
        let result = await deletion.execute(plan)

        if result.wasCancelled {
            // Nothing deleted; keep the cart exactly as it was (FR-REV-5).
            phase = .reviewing
            return
        }
        let deleted = Set(result.deletedAssetIDs)
        cart.removeAssets(deleted)
        scanStore.removeAssets(deleted)
        settings.recordFreed(result.bytesFreed)
        phase = .finished(result)
    }
}
