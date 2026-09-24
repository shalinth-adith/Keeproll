import Photos

nonisolated protocol PhotoLibraryProviding: Sendable {
    /// All screenshots, newest first, with sizes filled in.
    func fetchScreenshots() async -> [MediaItem]
    /// All videos, largest first, with sizes filled in.
    func fetchVideos() async -> [MediaItem]
}

/// Streams similar-photo groups as they're found. The live engine lands with the
/// similarity work; until then only the demo source provides one.
nonisolated protocol SimilarityScanning: Sendable {
    func scan() -> AsyncStream<SimilarGroup>
}

/// Finds duplicate contact groups. Live implementation lands with the contacts work.
nonisolated protocol ContactsScanning: Sendable {
    func findDuplicates() async -> [DuplicateContactGroup]
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
        let items = Self.enumerate(PHAsset.fetchAssets(with: .image, options: options), kind: .screenshot)
        let sized = await sizes.fillSizes(items)
        Log.photos.debug("Fetched \(sized.count) screenshots")
        return sized
    }

    @concurrent
    func fetchVideos() async -> [MediaItem] {
        let signpost = Signposts.scan.beginInterval("scan.videos")
        defer { Signposts.scan.endInterval("scan.videos", signpost) }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let items = Self.enumerate(PHAsset.fetchAssets(with: .video, options: options), kind: .video)
        let sized = await sizes.fillSizes(items).sorted { ($0.byteSize ?? 0) > ($1.byteSize ?? 0) }
        Log.photos.debug("Fetched \(sized.count) videos")
        return sized
    }

    private static func enumerate(_ result: PHFetchResult<PHAsset>, kind: MediaItem.Kind) -> [MediaItem] {
        var items: [MediaItem] = []
        items.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            items.append(item(from: asset, kind: kind))
        }
        return items
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
