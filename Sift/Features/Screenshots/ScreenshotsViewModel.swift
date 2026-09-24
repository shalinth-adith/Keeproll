import Foundation
import Observation

@Observable
final class ScreenshotsViewModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all, olderThan30Days
        var id: String { rawValue }
    }

    var filter: Filter = .all

    private let scanStore: ScanStore
    private let cart: CleanupCart
    private let now: () -> Date

    init(scanStore: ScanStore, cart: CleanupCart, now: @escaping () -> Date = Date.init) {
        self.scanStore = scanStore
        self.cart = cart
        self.now = now
    }

    var isLoading: Bool { scanStore.screenshots.isLoading }

    var items: [MediaItem] {
        let all = scanStore.screenshots.value ?? []
        switch filter {
        case .all:
            return all
        case .olderThan30Days:
            let cutoff = now().addingTimeInterval(-30 * 24 * 60 * 60)
            return all.filter { ($0.creationDate ?? .distantPast) < cutoff }
        }
    }

    var totalBytes: Int64 { items.reduce(0) { $0 + ($1.byteSize ?? 0) } }

    func isSelected(_ item: MediaItem) -> Bool { cart.contains(assetID: item.id) }

    var allVisibleSelected: Bool {
        !items.isEmpty && items.allSatisfy { cart.contains(assetID: $0.id) }
    }

    var selectedCount: Int { items.filter { cart.contains(assetID: $0.id) }.count }

    func toggle(_ item: MediaItem) {
        cart.toggle(item.cartItem(in: .screenshots))
    }

    /// Selects every visible screenshot, or clears them if all are already selected.
    func toggleSelectAll() {
        if allVisibleSelected {
            cart.removeAssets(items.map(\.id))
        } else {
            cart.add(items.map { $0.cartItem(in: .screenshots) })
        }
    }
}
