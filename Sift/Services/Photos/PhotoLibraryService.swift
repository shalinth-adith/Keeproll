import Photos

nonisolated protocol PhotoLibraryProviding: Sendable {
    /// All screenshots, newest first, with sizes filled in.
    func fetchScreenshots() async -> [MediaItem]
}

nonisolated final class PhotoLibraryService: PhotoLibraryProviding {
    private let sizes: AssetSizeService

    init(sizes: AssetSizeService) {
        self.sizes = sizes
    }

    @concurrent
    func fetchScreenshots() async -> [MediaItem] {
        let signpost = Signposts.scan.beginInterval("scan.screenshots")
        defer { Signposts.scan.endInterval("scan.screenshots", signpost) }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)

        var items: [MediaItem] = []
        items.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            items.append(Self.item(from: asset, kind: .screenshot))
        }
        let sized = await sizes.fillSizes(items)
        Log.photos.debug("Fetched \(sized.count) screenshots")
        return sized
    }

    static func item(from asset: PHAsset, kind: MediaItem.Kind) -> MediaItem {
        MediaItem(
            id: asset.localIdentifier,
            kind: kind,
            creationDate: asset.creationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.mediaType == .video ? asset.duration : nil,
            isFavorite: asset.isFavorite
        )
    }
}
