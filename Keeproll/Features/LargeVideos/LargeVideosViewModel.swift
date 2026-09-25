import Foundation
import Observation

@Observable
final class LargeVideosViewModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all, over100MB, over500MB
        var id: String { rawValue }

        var minimumBytes: Int64 {
            switch self {
            case .all: 0
            case .over100MB: 100_000_000
            case .over500MB: 500_000_000
            }
        }
    }

    var filter: Filter = .all

    private let scanStore: ScanStore
    private let cart: CleanupCart
    private let router: AppRouter

    init(scanStore: ScanStore, cart: CleanupCart, router: AppRouter) {
        self.scanStore = scanStore
        self.cart = cart
        self.router = router
    }

    var isLoading: Bool { scanStore.videos.isLoading }

    /// Largest first (FR-VID-1), narrowed by the size filter (FR-VID-3).
    var items: [MediaItem] {
        (scanStore.videos.value ?? []).filter { ($0.byteSize ?? 0) >= filter.minimumBytes }
    }

    var totalBytes: Int64 { items.reduce(0) { $0 + ($1.byteSize ?? 0) } }
    var selectedCount: Int { items.filter { cart.contains(assetID: $0.id) }.count }

    func isSelected(_ item: MediaItem) -> Bool { cart.contains(assetID: item.id) }
    func toggle(_ item: MediaItem) { cart.toggle(item.cartItem(in: .videos)) }
    func preview(_ item: MediaItem) { router.previewVideo(item.id) }
    func compress(_ item: MediaItem) { router.sheet = .compress(item) }

    /// Estimated saving, or nil when compressing isn't worth offering (too small, already
    /// compact, or already compressed once).
    func compressSaving(for item: MediaItem) -> Int64? {
        scanStore.compressedVideos.contains(item.id) ? nil : VideoCompressionService.worthCompressing(item)
    }
}
