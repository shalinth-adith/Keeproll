import Observation

/// App-wide selection of everything the user intends to remove. The Review screen reads
/// this, and it's the only source a `CleanupPlan` is built from (D10).
@Observable
final class CleanupCart {
    private(set) var items: [String: CartItem] = [:]

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }
    var totalBytes: Int64 { items.values.reduce(0) { $0 + $1.bytes } }

    func contains(assetID: String) -> Bool {
        items["asset:\(assetID)"] != nil
    }

    func toggle(_ item: CartItem) {
        if items[item.key] == nil { items[item.key] = item } else { items[item.key] = nil }
    }

    func add(_ newItems: some Sequence<CartItem>) {
        for item in newItems { items[item.key] = item }
    }

    func remove(_ item: CartItem) {
        items[item.key] = nil
    }

    func removeAssets(_ ids: some Sequence<String>) {
        for id in ids { items["asset:\(id)"] = nil }
    }

    func removeAll(in category: CleanupCategory) {
        items = items.filter { $0.value.category != category }
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
