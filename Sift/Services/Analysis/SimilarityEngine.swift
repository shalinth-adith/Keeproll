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
    private let timings = StageTimings()

    init(sizes: AssetSizeService, cache: ScanCache, config: SimilarityConfig = .current) {
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

    /// PHAsset is an immutable snapshot that PhotoKit documents as safe to read from
    /// any thread; boxing it saves re-fetching every photo by id in the workers.
    private struct AssetBox: @unchecked Sendable { let asset: PHAsset }

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
        let items = photos.map { PhotoLibraryService.item(from: $0, kind: .photo) }
        let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var sharpnessByID: [String: Float] = [:]
        var groupIDs: [String: UUID] = [:]        // anchor asset id → stable group id
        var emitted: [UUID: [String]] = [:]       // group id → member ids last sent
        var cacheHits = 0
        var blurry: [MediaItem] = []
        var lastEmit = Date()
        #if DEBUG
        let probe = CalibrationProbe()
        grouper.onCompare = { probe.record(a: $0, b: $1, featureDistance: $2, hashDistance: $3, seconds: $4) }
        #endif

        // One continuous pipeline, no batches: keep `width` photos in flight, start the
        // next as each finishes, and feed results to the grouper in date order through a
        // small reorder buffer. (Fixed batches waited on their slowest photo each time:
        // ~19 s of a 50 s scan on a 7,724-photo library.)
        let width = max(4, ProcessInfo.processInfo.activeProcessorCount * 2)
        var pending: [Int: Loaded] = [:]
        var nextToFeed = 0
        let loadStart = Date()

        await withTaskGroup(of: Loaded.self) { group in
            var nextToStart = 0
            func startNext() {
                guard nextToStart < total else { return }
                let index = nextToStart
                nextToStart += 1
                let box = AssetBox(asset: photos[index])
                let item = items[index]
                let wantsPrint = needsPrint[index]
                group.addTask { await self.features(for: box, item: item, index: index, wantsPrint: wantsPrint) }
            }
            for _ in 0..<width { startNext() }

            for await loaded in group {
                if Task.isCancelled {
                    group.cancelAll()
                    return
                }
                pending[loaded.index] = loaded
                startNext()

                while let entry = pending.removeValue(forKey: nextToFeed) {
                    nextToFeed += 1
                    guard let features = entry.features else { continue } // iCloud-only, no local thumbnail
                    if entry.fromCache { cacheHits += 1 }
                    grouper.add(features)
                    sharpnessByID[features.id] = features.sharpness
                    let item = items[entry.index]
                    if features.sharpness < config.blurThreshold, !item.isFavorite { blurry.append(item) }
                }

                // About once a second: stream new groups and blurry photos to the UI.
                if Date().timeIntervalSince(lastEmit) > 1 {
                    let emitStart = Date()
                    if !blurry.isEmpty {
                        out.yield(.blurry(await sizes.fillSizes(blurry)))
                        blurry.removeAll()
                    }
                    await emitChanges(grouper: grouper, itemsByID: itemsByID, sharpnessByID: sharpnessByID,
                                      groupIDs: &groupIDs, emitted: &emitted, out: out)
                    timings.addWall(emit: Date().timeIntervalSince(emitStart))
                    out.yield(.progress(processed: nextToFeed, total: total))
                    lastEmit = Date()
                }
            }
        }
        guard !Task.isCancelled else { return }
        timings.addWall(load: Date().timeIntervalSince(loadStart))

        if !blurry.isEmpty { out.yield(.blurry(await sizes.fillSizes(blurry))) }
        await emitChanges(grouper: grouper, itemsByID: itemsByID, sharpnessByID: sharpnessByID,
                          groupIDs: &groupIDs, emitted: &emitted, out: out)
        out.yield(.progress(processed: total, total: total))

        await cache.save()
        if !printer.isAvailable { Log.perf.info("Vision unavailable this run; similar shots matched by hash") }
        let seconds = Date().timeIntervalSince(started)
        Log.perf.info("Similarity scan: \(total) photos, \(emitted.count) groups, \(cacheHits) cached, \(seconds, format: .fixed(precision: 2))s")
        #if DEBUG
        print("[calibration] stages " + timings.summary() + " cached=\(cacheHits)"
              + String(format: " visionExec=%.1fs prints=%d", printer.execSeconds, printer.printCount))
        #endif
        #if DEBUG
        let calibration = probe.finish(sharpness: sharpnessByID, groups: grouper.groups().map(\.memberIDs),
                                       photos: total, seconds: seconds)
        out.yield(.calibration(calibration))
        #endif
    }

    private func features(for box: AssetBox, item: MediaItem, index: Int, wantsPrint: Bool) async -> Loaded {
        let id = item.id
        // File size, read here in parallel (and cached) rather than later, one at a time,
        // inside AssetSizeService when groups are emitted.
        if await cache.size(for: id, modified: item.modificationDate) == nil,
           let bytes = AssetSizeService.fileSize(of: box.asset) {
            await cache.storeSize(bytes, for: id, modified: item.modificationDate)
        }
        // Reuse the cache unless a print is wanted, missing, and Vision can still make one.
        // An empty cached print means "Vision tried and couldn't": don't retry every scan.
        if let cached = await cache.feature(for: id, modified: item.modificationDate),
           !wantsPrint || cached.print != nil || !printer.isAvailable {
            let print = wantsPrint && cached.print?.isEmpty == false ? cached.print : nil
            return Loaded(index: index, features: AssetFeatures(
                id: id, date: item.creationDate, dHash: cached.dHash, sharpness: cached.sharpness,
                print: print, isFavorite: item.isFavorite,
                pixelCount: item.pixelWidth * item.pixelHeight
            ), fromCache: true)
        }
        let t0 = Date()
        guard let image = await thumbnail(for: box.asset) else {
            timings.add(thumbnail: Date().timeIntervalSince(t0), analysis: 0, vision: 0, missing: true)
            return Loaded(index: index, features: nil, fromCache: false)
        }
        let t1 = Date()
        let computed: (UInt64, Float)? = autoreleasepool {
            guard let hash = ImageAnalysis.dHash(image) else { return nil }
            return (hash, ImageAnalysis.sharpness(image))
        }
        guard let (hash, sharpness) = computed else {
            return Loaded(index: index, features: nil, fromCache: false)
        }
        let t2 = Date()
        let print = wantsPrint ? await printer.featurePrint(for: image) : nil
        timings.add(thumbnail: t1.timeIntervalSince(t0), analysis: t2.timeIntervalSince(t1),
                    vision: wantsPrint ? Date().timeIntervalSince(t2) : 0, missing: false)
        // Record a Vision failure as an empty print, unless Vision was switched off by the
        // watchdog (then a later run should try again).
        let cachedPrint: [Float]? = wantsPrint && print == nil && printer.isAvailable ? [] : print
        await cache.store(.init(modified: item.modificationDate?.timeIntervalSinceReferenceDate ?? 0,
                                dHash: hash, sharpness: sharpness, print: cachedPrint), for: id)
        return Loaded(index: index, features: AssetFeatures(
            id: id, date: item.creationDate, dHash: hash, sharpness: sharpness, print: print,
            isFavorite: item.isFavorite, pixelCount: item.pixelWidth * item.pixelHeight
        ), fromCache: false)
    }

    /// The fast local thumbnail, falling back to a local full-quality decode.
    ///
    /// `.fastFormat` returns PhotoKit's cached thumbnail with no decode: quick, and fine for
    /// hashing, sharpness and Vision. It isn't always there (freshly imported photos have
    /// none yet: error 3303), so fall back to `.highQualityFormat`. Neither touches the
    /// network (D7); photos that exist only in iCloud are skipped.
    private func thumbnail(for asset: PHAsset) async -> CGImage? {
        if let fast = await requestImage(asset, mode: .fastFormat) { return fast }
        return await requestImage(asset, mode: .highQualityFormat)
    }

    private func requestImage(_ asset: PHAsset, mode: PHImageRequestOptionsDeliveryMode) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = mode
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

    /// Sends upserts for groups that changed since the last emit and removes for groups
    /// that merged into another. O(changes), so emitting doesn't slow the pipeline.
    private func emitChanges(grouper: SimilarityGrouper, itemsByID: [String: MediaItem], sharpnessByID: [String: Float],
                             groupIDs: inout [String: UUID], emitted: inout [UUID: [String]],
                             out: AsyncStream<SimilarityEvent>.Continuation) async {
        let (changed, vanished) = grouper.drainChanges()
        for anchorID in vanished {
            if let id = groupIDs.removeValue(forKey: anchorID), emitted.removeValue(forKey: id) != nil {
                out.yield(.remove(id))
            }
        }
        for group in changed {
            let id = groupIDs[group.anchorID] ?? UUID()
            groupIDs[group.anchorID] = id
            let members = group.memberIDs
            guard emitted[id].map(Set.init) != Set(members) else { continue }

            let sized = await sizes.fillSizes(members.compactMap { itemsByID[$0] })
            let ranked = BestShotRanker.rank(sized.compactMap { item -> BestShotRanker.Candidate? in
                guard let sharpness = sharpnessByID[item.id] else { return nil }
                return .init(id: item.id, isFavorite: item.isFavorite, sharpness: sharpness,
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
    }

    /// Summed per-stage time across the task group (so it exceeds wall time when parallel).
    nonisolated final class StageTimings: @unchecked Sendable {
        private let lock = NSLock()
        private var thumbnail = 0.0, analysis = 0.0, vision = 0.0
        private var loadWall = 0.0, emitWall = 0.0
        private var count = 0, missing = 0

        func addWall(load: Double = 0, emit: Double = 0) {
            lock.withLock { loadWall += load; emitWall += emit }
        }

        func add(thumbnail t: Double, analysis a: Double, vision v: Double, missing m: Bool) {
            lock.withLock {
                thumbnail += t; analysis += a; vision += v; count += 1
                if m { missing += 1 }
            }
        }

        func summary() -> String {
            lock.withLock {
                String(format: "computed=%d missingThumbnail=%d thumbnailSum=%.1fs analysisSum=%.1fs visionSum=%.1fs loadWall=%.1fs emitWall=%.1fs",
                       count, missing, thumbnail, analysis, vision, loadWall, emitWall)
            }
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
