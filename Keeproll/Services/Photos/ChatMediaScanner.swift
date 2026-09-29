import Photos

/// Finds images that were saved from messaging apps (bonus: smart categories).
nonisolated protocol ChatMediaScanning: Sendable {
    func findChatSaved() async -> [ChatSavedItem]
}

/// Walks every non-screenshot photo, gathers its provenance (filename and type from
/// PhotoKit, camera metadata from a header read, the iOS 18 utility flag from a
/// thumbnail) and asks `ProvenanceEngine`. Header reads and utility flags are cached in
/// `ScanCache`, so a rescan costs one PhotoKit enumeration.
nonisolated final class ChatMediaScanner: ChatMediaScanning {
    private let sizes: AssetSizeService
    private let cache: ScanCache
    private let aesthetics = AestheticsService()

    init(sizes: AssetSizeService, cache: ScanCache) {
        self.sizes = sizes
        self.cache = cache
    }

    private struct AssetBox: @unchecked Sendable { let asset: PHAsset } // immutable PhotoKit snapshot

    @concurrent
    func findChatSaved() async -> [ChatSavedItem] {
        let signpost = Signposts.scan.beginInterval("scan.chats")
        defer { Signposts.scan.endInterval("scan.chats", signpost) }
        let started = Date()

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            // Screenshots have their own categories; favourites are never suggested.
            if !asset.mediaSubtypes.contains(.photoScreenshot), !asset.isFavorite { assets.append(asset) }
        }
        guard !assets.isEmpty else { return [] }

        let width = max(4, ProcessInfo.processInfo.activeProcessorCount * 2)
        var found: [ChatSavedItem] = []
        var headerReads = 0
        await withTaskGroup(of: (ChatSavedItem?, Bool).self) { group in
            var next = 0
            func start() {
                guard next < assets.count else { return }
                let box = AssetBox(asset: assets[next])
                next += 1
                group.addTask { await self.evaluate(box) }
            }
            for _ in 0..<width { start() }
            for await (item, readHeader) in group {
                if Task.isCancelled { group.cancelAll(); return }
                if readHeader { headerReads += 1 }
                if let item { found.append(item) }
                start()
            }
        }
        guard !Task.isCancelled else { return [] }

        let sized = await sizes.fillSizes(found.map(\.item))
        let sizedByID = Dictionary(sized.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let items = found.compactMap { entry -> ChatSavedItem? in
            guard let item = sizedByID[entry.id] else { return nil }
            return ChatSavedItem(item: item, verdict: entry.verdict)
        }
        .sorted { a, b in
            if a.verdict.confidence != b.verdict.confidence { return a.verdict.confidence > b.verdict.confidence }
            return (a.item.byteSize ?? 0) > (b.item.byteSize ?? 0)
        }
        await cache.save()
        Log.perf.info("Chat-media scan: \(assets.count) photos, \(items.count) flagged, \(headerReads) header reads, \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s")
        return items
    }

    /// (verdict, whether a header had to be read).
    private func evaluate(_ box: AssetBox) async -> (ChatSavedItem?, Bool) {
        let asset = box.asset
        let item = PhotoLibraryService.item(from: asset, kind: .photo)
        let identity = AssetHeaderReader.identity(of: asset)
        var readHeader = false

        let cached = await cache.provenance(for: item.id, modified: item.modificationDate)
        var hasCamera = cached?.hasCameraMetadata
        var isUtility = cached?.isUtility
        if cached == nil {
            readHeader = true
            hasCamera = await AssetHeaderReader.hasCameraMetadata(asset)
            // Only images that might be forwards are worth a Vision pass.
            if hasCamera != true, aesthetics.isSupported,
               let image = await AssetThumbnailLoader.image(for: asset, side: 256) {
                isUtility = await aesthetics.isUtility(image)
            }
            await cache.store(ScanCache.ProvenanceRecord(modified: item.modificationDate?.timeIntervalSinceReferenceDate ?? 0,
                                                         hasCameraMetadata: hasCamera, isUtility: isUtility), for: item.id)
        }

        let provenance = AssetProvenance(
            originalFilename: identity.filename, uniformType: identity.uti,
            pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight,
            hasCameraMetadata: hasCamera, hasLocation: asset.location != nil,
            isFavorite: asset.isFavorite, isUtility: isUtility
        )
        guard let verdict = ProvenanceEngine.verdict(for: provenance) else { return (nil, readHeader) }
        return (ChatSavedItem(item: item, verdict: verdict), readHeader)
    }
}
