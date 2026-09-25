import Foundation
import Observation

@Observable
final class SimilarPhotosViewModel {
    private let scanStore: ScanStore
    private let cart: CleanupCart
    private let router: AppRouter

    init(scanStore: ScanStore, cart: CleanupCart, router: AppRouter) {
        self.scanStore = scanStore
        self.cart = cart
        self.router = router
    }

    var groups: [SimilarGroup] { scanStore.similar.value ?? [] }
    var isScanning: Bool { scanStore.similarProgress != nil }
    var isLoading: Bool { scanStore.similar.isLoading && groups.isEmpty }
    var freeableBytes: Int64 { scanStore.similarBytes }
    var photoCount: Int { groups.reduce(0) { $0 + $1.members.count } }
    var selectedCount: Int { groups.flatMap(\.members).filter { cart.contains(assetID: $0.id) }.count }

    func isSelected(_ item: MediaItem) -> Bool { cart.contains(assetID: item.id) }

    func allOthersSelected(in group: SimilarGroup) -> Bool {
        !group.othersThanBest.isEmpty && group.othersThanBest.allSatisfy { cart.contains(assetID: $0.id) }
    }

    /// Every non-best photo in every group is selected.
    var smartSelectActive: Bool {
        !groups.isEmpty && groups.allSatisfy { allOthersSelected(in: $0) }
    }

    func toggle(_ item: MediaItem) {
        cart.toggle(item.cartItem(in: .similar))
    }

    /// "Keep best only" for one group, or undo it (FR-SIM-4).
    func toggleOthers(in group: SimilarGroup) {
        if allOthersSelected(in: group) {
            cart.removeAssets(group.othersThanBest.map(\.id))
        } else {
            cart.removeAssets([group.bestID])
            cart.add(group.othersThanBest.map { $0.cartItem(in: .similar) })
        }
    }

    /// Smart select across all groups, or clear it.
    func toggleSmartSelect() {
        if smartSelectActive {
            cart.removeAssets(groups.flatMap(\.othersThanBest).map(\.id))
        } else {
            cart.removeAssets(groups.map(\.bestID))
            cart.add(groups.flatMap(\.othersThanBest).map { $0.cartItem(in: .similar) })
        }
    }

    func makeBest(_ item: MediaItem, in group: SimilarGroup) {
        cart.removeAssets([item.id])
        scanStore.setBest(item.id, in: group.id)
    }

    func openCompare(_ item: MediaItem, in group: SimilarGroup) {
        router.open(.compare(groupID: group.id, startID: item.id))
    }

    func group(id: UUID) -> SimilarGroup? { groups.first { $0.id == id } }
}
