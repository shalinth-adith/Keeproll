import Photos
import UIKit

/// The live similar-photo scan (FR-SIM-1/2, bonus blurry detection).
///
/// Walks every photo (screenshots excluded, D8) in date order, in batches:
/// 1. For each photo, reuse cached features or load a 256 px thumbnail (never from
///    iCloud, D7) and compute a dHash, a sharpness score and, only if another photo was
///    taken within the time window, a Vision feature print.
/// 2. Feed the features to `SimilarityGrouper` in date order.
/// 3. After each batch, stream the changed groups and new blurry photos to the UI.
nonisolated final class SimilarityEngine: SimilarityScanning {
    private let sizes: AssetSizeService
    private let cache: ScanCache
    private let config: SimilarityConfig
    private let printer = FeaturePrintService()

    init(sizes: AssetSizeService, cache: ScanCache, config: SimilarityConfig = .standard) {
        self.sizes = sizes
        self.cache = cache
        self.config = config
    }

    func scan() -> AsyncStream<SimilarityEvent> {
        AsyncStream { continuation in
            let task = Task {
                await self.run(continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Pipeline

    private struct Loaded: Sendable {
        let index: Int
        let features: AssetFeatures?
        let fromCache: Bool
    }

    @concurrent
    private func run(_ out: AsyncStream<SimilarityEvent>.Continuation) async {
        let signpost = Signposts.scan.beginInterval("scan.similar")
        defer { Signposts.scan.endInterval("scan.similar", signpost) }
        let started = Date()

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        // Screenshots have their own category (D8). Filtered here rather than with a
        // `mediaSubtypes & … == 0` predicate, which PhotoKit doesn't evaluate reliably.
        var photos: [PHAsset] = []
        photos.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            if !asset.mediaSubtypes.contains(.photoScreenshot) { photos.append(asset) }
        }
        let total = photos.count
        out.yield(.progress(processed: 0, total: total))
        guard total > 0 else { return }

        // Which photos have a neighbour close enough in time to be a "similar shot"?
        // Only those get a (comparatively expensive) feature print.
        let dates = photos.map(\.creationDate)
        let needsPrint = Self.neighbourFlags(dates, window: config.timeWindow)

        let grouper = SimilarityGrouper(config: config)
        var items: [MediaItem] = []
        items.reserveCapacity(total)
        var groupIDs: [String: UUID] = [:]        // anchor asset id → stable group id
        var emitted: [UUID: [String]] = [:]       // group id → member ids last sent
        var cacheHits = 0

        var start = 0
        while start < total {
            guard !Task.isCancelled else { return }
            let end = min(start + config.batchSize, total)
            let assets = Array(photos[start..<end])
            let batchItems = assets.map { PhotoLibraryService.item(from: $0, kind: .photo) }
            items.append(contentsOf: batchItems)

            let loaded = await loadBatch(assets, items: batchItems, offset: start, needsPrint: needsPrint)
            var blurry: [MediaItem] = []
            for entry in loaded.sorted(by: { $0.index < $1.index }) {
                guard let features = entry.features else { continue } // no local thumbnail (iCloud-only)
                if entry.fromCache { cacheHits += 1 }
                grouper.add(features)
                let item = items[entry.index]
                if features.sharpness < config.blurThreshold, !item.isFavorite { blurry.append(item) }
            }

            if !blurry.isEmpty { out.yield(.blurry(await sizes.fillSizes(blurry))) }
            await emitChanges(grouper: grouper, items: items, groupIDs: &groupIDs, emitted: &emitted, out: out)
            out.yield(.progress(processed: end, total: total))
            start = end
        }

        await cache.save()
        if !printer.isAvailable { Log.perf.info("Vision unavailable this run; similar shots matched by hash") }
        let seconds = Date().timeIntervalSince(started)
        Log.perf.info("Similarity scan: \(total) photos, \(emitted.count) groups, \(cacheHits) cached, \(seconds, format: .fixed(precision: 2))s")
    }

    /// Loads features for one batch with bounded parallelism.
    private func loadBatch(_ assets: [PHAsset], items: [MediaItem], offset: Int, needsPrint: [Bool]) async -> [Loaded] {
        let requests = assets.enumerated().map { ($0.offset + offset, $0.element.localIdentifier, items[$0.offset]) }
        let width = max(2, ProcessInfo.processInfo.activeProcessorCount)
        return await withTaskGroup(of: Loaded.self) { group in
            var results: [Loaded] = []
            var next = 0
            func enqueue() {
                guard next < requests.count else { return }
                let (index, id, item) = requests[next]
                let wantsPrint = needsPrint[index]
                next += 1
                group.addTask { await self.features(for: id, item: item, index: index, wantsPrint: wantsPrint) }
            }
            for _ in 0..<width { enqueue() }
            for await loaded in group {
                results.append(loaded)
                enqueue()
            }
            return results
        }
    }

    private func features(for id: String, item: MediaItem, index: Int, wantsPrint: Bool) async -> Loaded {
        // Reuse the cache unless a print is wanted, missing, and Vision can still make one.
        if let cached = await cache.feature(for: id, modified: item.modificationDate),
           !wantsPrint || cached.print != nil || !printer.isAvailable {
            return Loaded(index: index, features: AssetFeatures(
                id: id, date: item.creationDate, dHash: cached.dHash, sharpness: cached.sharpness,
                print: wantsPrint ? cached.print : nil, isFavorite: item.isFavorite,
                pixelCount: item.pixelWidth * item.pixelHeight
            ), fromCache: true)
        }
        guard let image = await thumbnail(for: id) else {
            return Loaded(index: index, features: nil, fromCache: false)
        }
        let computed: (UInt64, Float)? = autoreleasepool {
            guard let hash = ImageAnalysis.dHash(image) else { return nil }
            return (hash, ImageAnalysis.sharpness(image))
        }
        guard let (hash, sharpness) = computed else {
            return Loaded(index: index, features: nil, fromCache: false)
        }
        let print = wantsPrint ? await printer.featurePrint(for: image) : nil
        await cache.store(.init(modified: item.modificationDate?.timeIntervalSinceReferenceDate ?? 0,
                                dHash: hash, sharpness: sharpness, print: print), for: id)
        return Loaded(index: index, features: AssetFeatures(
            id: id, date: item.creationDate, dHash: hash, sharpness: sharpness, print: print,
            isFavorite: item.isFavorite, pixelCount: item.pixelWidth * item.pixelHeight
        ), fromCache: false)
    }

    private func thumbnail(for id: String) async -> CGImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false // never download from iCloud (D7)
        let side = config.thumbnailSide
        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFit, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
        return image?.cgImage
    }

    /// Sends upserts for new or grown groups and removes for groups that merged away.
    private func emitChanges(grouper: SimilarityGrouper, items: [MediaItem],
                             groupIDs: inout [String: UUID], emitted: inout [UUID: [String]],
                             out: AsyncStream<SimilarityEvent>.Continuation) async {
        let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let featuresByID = Dictionary(grouper.features.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var live = Set<UUID>()

        for group in grouper.groups() {
            let id = groupIDs[group.anchorID] ?? UUID()
            groupIDs[group.anchorID] = id
            live.insert(id)
            let members = group.memberIDs
            guard emitted[id].map(Set.init) != Set(members) else { continue }

            let sized = await sizes.fillSizes(members.compactMap { itemsByID[$0] })
            let ranked = BestShotRanker.rank(sized.compactMap { item -> BestShotRanker.Candidate? in
                guard let features = featuresByID[item.id] else { return nil }
                return .init(id: item.id, isFavorite: item.isFavorite, sharpness: features.sharpness,
                             pixelCount: item.pixelWidth * item.pixelHeight, date: item.creationDate,
                             bytes: item.byteSize ?? 0)
            }, exactDuplicates: group.isExactDuplicate)
            let sizedByID = Dictionary(sized.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let memberItems = ranked.compactMap { sizedByID[$0] }
            guard let best = ranked.first else { continue }
            emitted[id] = members
            out.yield(.upsert(SimilarGroup(id: id, kind: group.isExactDuplicate ? .exactDuplicate : .similar,
                                           members: memberItems, bestID: best)))
        }
        for id in Set(emitted.keys).subtracting(live) {
            emitted[id] = nil
            out.yield(.remove(id))
        }
    }

    /// `true` for photos with another photo within `window` seconds (input sorted by date).
    static func neighbourFlags(_ dates: [Date?], window: TimeInterval) -> [Bool] {
        var flags = [Bool](repeating: false, count: dates.count)
        var previous: (index: Int, date: Date)?
        for (index, date) in dates.enumerated() {
            guard let date else { continue }
            if let previous, date.timeIntervalSince(previous.date) <= window {
                flags[index] = true
                flags[previous.index] = true
            }
            previous = (index, date)
        }
        return flags
    }
}
