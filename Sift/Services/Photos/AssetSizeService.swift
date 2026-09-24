import Photos

/// Reads on-device file sizes for assets.
///
/// PhotoKit has no public file-size API. `PHAssetResource`'s `fileSize` via KVC is widely
/// used but undocumented, so it's read defensively; if it's missing, the size is
/// estimated from the pixel count and flagged `sizeIsEstimated`. Real sizes are kept in
/// the persistent `ScanCache`, so rescans don't re-read resources.
actor AssetSizeService {
    private let cache: ScanCache?
    private var memo: [String: Int64] = [:]

    init(cache: ScanCache? = nil) {
        self.cache = cache
    }

    func fillSizes(_ items: [MediaItem]) async -> [MediaItem] {
        var missing: [String] = []
        for item in items where memo[item.id] == nil {
            if let cached = await cache?.size(for: item.id, modified: item.modificationDate) {
                memo[item.id] = cached
            } else {
                missing.append(item.id)
            }
        }
        if !missing.isEmpty {
            // Resource reads are slow (~ms each) and independent: do them in parallel,
            // off this actor, so other callers aren't queued behind a big first read.
            let found = await Self.readSizes(missing)
            for (id, size, modified) in found {
                memo[id] = size
                await cache?.storeSize(size, for: id, modified: modified)
            }
        }
        return items.map { item in
            var item = item
            if let size = memo[item.id] {
                item.byteSize = size
            } else {
                item.byteSize = Self.estimate(item)
                item.sizeIsEstimated = true
            }
            return item
        }
    }

    private struct Boxed: @unchecked Sendable { let assets: [PHAsset] } // immutable snapshots

    @concurrent
    private static func readSizes(_ ids: [String]) async -> [(String, Int64, Date?)] {
        var assets: [PHAsset] = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in assets.append(asset) }
        let lanes = max(2, ProcessInfo.processInfo.activeProcessorCount)
        let chunk = max(1, (assets.count + lanes - 1) / lanes)
        let chunks = stride(from: 0, to: assets.count, by: chunk).map { Boxed(assets: Array(assets[$0..<min($0 + chunk, assets.count)])) }
        return await withTaskGroup(of: [(String, Int64, Date?)].self) { group in
            for box in chunks {
                group.addTask {
                    box.assets.compactMap { asset in
                        fileSize(of: asset).map { (asset.localIdentifier, $0, asset.modificationDate) }
                    }
                }
            }
            var all: [(String, Int64, Date?)] = []
            for await part in group { all += part }
            return all
        }
    }

    func forget(_ ids: some Sequence<String>) {
        for id in ids { memo[id] = nil }
    }

    /// Sum of the original resources' sizes. Static (no actor hop), so the scan's worker
    /// tasks can read sizes in parallel.
    static func fileSize(of asset: PHAsset) -> Int64? {
        let resources = PHAssetResource.assetResources(for: asset)
        // Count the original resources; ignore adjustment data and derived renders.
        let originals = resources.filter {
            [.photo, .video, .fullSizePhoto, .fullSizeVideo, .pairedVideo, .alternatePhoto].contains($0.type)
        }
        let sizes = originals.compactMap { ($0.value(forKey: "fileSize") as? NSNumber)?.int64Value }
        guard !sizes.isEmpty else { return nil }
        return sizes.reduce(0, +)
    }

    /// Rough fallback: HEIC averages ~0.35 bytes per pixel; video ~1 MB per second at 1080p.
    private static func estimate(_ item: MediaItem) -> Int64 {
        if let duration = item.duration { return Int64(duration * 1_000_000) }
        return Int64(Double(item.pixelWidth * item.pixelHeight) * 0.35)
    }
}
