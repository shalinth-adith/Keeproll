import Photos

/// Reads on-device file sizes for assets.
///
/// PhotoKit has no public file-size API. `PHAssetResource`'s `fileSize` via KVC is widely
/// used but undocumented, so it's read defensively; if it's missing, the size is
/// estimated from the pixel count and flagged `sizeIsEstimated`. Results are memoised
/// for the life of the process (the persistent cache arrives with the Day 2 ScanCache).
actor AssetSizeService {
    private var cache: [String: Int64] = [:]

    func fillSizes(_ items: [MediaItem]) -> [MediaItem] {
        let missing = items.filter { cache[$0.id] == nil }.map(\.id)
        if !missing.isEmpty {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: missing, options: nil)
            assets.enumerateObjects { asset, _, _ in
                if let size = Self.fileSize(of: asset) {
                    self.cache[asset.localIdentifier] = size
                }
            }
        }
        return items.map { item in
            var item = item
            if let size = cache[item.id] {
                item.byteSize = size
            } else {
                item.byteSize = Self.estimate(item)
                item.sizeIsEstimated = true
            }
            return item
        }
    }

    func forget(_ ids: some Sequence<String>) {
        for id in ids { cache[id] = nil }
    }

    private static func fileSize(of asset: PHAsset) -> Int64? {
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
