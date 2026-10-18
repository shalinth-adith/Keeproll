import AVFoundation
import Photos

nonisolated protocol SmartTrimScanning: Sendable {
    /// Videos with dead stretches, biggest saving first.
    func findCandidates() async -> [TrimCandidate]
}

nonisolated struct TrimResult: Sendable, Equatable {
    let newAssetID: String
    let originalBytes: Int64
    let newBytes: Int64
    var savedBytes: Int64 { max(originalBytes - newBytes, 0) }
}

nonisolated enum TrimError: LocalizedError, Equatable {
    case notSmaller

    var errorDescription: String? {
        String(localized: "The trimmed copy wouldn't be smaller, because the dark parts take almost no space. Nothing was changed.")
    }
}

nonisolated protocol VideoTrimming: Sendable {
    func trim(_ candidate: TrimCandidate, progress: @escaping @Sendable (Double) -> Void) async throws -> TrimResult
}

/// Smart Trim (bonus): finds the dark or blank stretches of videos and saves a copy
/// without them.
///
/// Scanning samples about one frame a second at 32 px from local videos only (D7: no
/// iCloud downloads), and caches the result per video, so each clip is analysed once.
/// Trimming follows the compression pattern: the trimmed copy is added to the library
/// first, the original only goes to Review (D10).
nonisolated final class SmartTrimService: SmartTrimScanning, VideoTrimming {
    private let photos: PhotoLibraryProviding
    private let cache: ScanCache

    init(photos: PhotoLibraryProviding, cache: ScanCache) {
        self.photos = photos
        self.cache = cache
    }

    // MARK: - Scanning

    @concurrent
    func findCandidates() async -> [TrimCandidate] {
        let signpost = Signposts.scan.beginInterval("scan.trim")
        defer { Signposts.scan.endInterval("scan.trim", signpost) }
        let started = Date()
        let videos = await photos.fetchVideos().filter {
            ($0.duration ?? 0) >= SmartTrimEngine.minimumDuration && !$0.isFavorite && !$0.isCloudOnly
        }
        guard !videos.isEmpty else { return [] }

        var found: [TrimCandidate] = []
        var analysed = 0
        await withTaskGroup(of: (TrimCandidate?, Bool).self) { group in
            var next = 0
            func start() {
                guard next < videos.count else { return }
                let item = videos[next]
                next += 1
                group.addTask { await self.evaluate(item) }
            }
            // Two at a time: decoding is the cost, and a scan shouldn't heat the phone.
            for _ in 0..<2 { start() }
            for await (candidate, ran) in group {
                if Task.isCancelled { group.cancelAll(); return }
                if ran { analysed += 1 }
                if let candidate { found.append(candidate) }
                start()
            }
        }
        guard !Task.isCancelled else { return [] }
        await cache.save()
        Log.perf.info("Smart Trim scan: \(videos.count) videos, \(found.count) to trim, \(analysed) analysed, \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s")
        return found.sorted { $0.estimatedSaving > $1.estimatedSaving }
    }

    /// Returns the candidate (if any) and whether frames were actually decoded.
    private func evaluate(_ item: MediaItem) async -> (TrimCandidate?, Bool) {
        let duration = item.duration ?? 0
        if let cached = await cache.trim(for: item.id, modified: item.modificationDate) {
            return (Self.offered(TrimCandidate(item: item, deadRanges: cached.ranges, deadBytes: cached.deadBytes)), false)
        }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil).firstObject,
              let box = try? await VideoCompressionService.avAsset(for: asset, allowsNetwork: false) else {
            return (nil, false) // not on this iPhone; try again next scan
        }
        guard let samples = await Self.samples(of: box.asset, duration: duration) else { return (nil, true) }
        let ranges = SmartTrimEngine.deadRanges(samples: samples, duration: duration)
        let deadBytes = ranges.isEmpty ? nil : await Self.compressedBytes(of: box.asset, in: ranges)
        await cache.store(trim: ranges, deadBytes: deadBytes, for: item.id, modified: item.modificationDate)
        return (Self.offered(TrimCandidate(item: item, deadRanges: ranges, deadBytes: deadBytes)), true)
    }

    private static func offered(_ candidate: TrimCandidate) -> TrimCandidate? {
        !candidate.deadRanges.isEmpty && candidate.isWorthOffering ? candidate : nil
    }

    /// Sums the compressed sample sizes inside `ranges`, without decoding: the bytes a
    /// lossless cut really frees.
    private static func compressedBytes(of asset: AVAsset, in ranges: [TrimRange]) async -> Int64? {
        guard let tracks = try? await asset.load(.tracks), !tracks.isEmpty else { return nil }
        var total: Int64 = 0
        let media = tracks.filter { $0.mediaType == .video || $0.mediaType == .audio }
        // One reader per track and range: draining one output of a multi-output reader
        // before the others can stall on interleaved files.
        for range in ranges {
            for track in media {
                guard let reader = try? AVAssetReader(asset: asset) else { return nil }
                reader.timeRange = CMTimeRange(start: CMTime(seconds: range.start, preferredTimescale: 600),
                                               end: CMTime(seconds: range.end, preferredTimescale: 600))
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil) // compressed samples, no decode
                guard reader.canAdd(output) else { continue }
                reader.add(output)
                guard reader.startReading() else { return nil }
                // The reader starts at the keyframe before `start`, so count only samples
                // that are actually shown inside the range.
                while let sample = output.copyNextSampleBuffer() {
                    let shown = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    if shown >= range.start && shown < range.end {
                        total += Int64(CMSampleBufferGetTotalSampleSize(sample))
                    }
                    if Task.isCancelled { reader.cancelReading(); return nil }
                }
            }
        }
        return total
    }

    /// Tiny frames at about one a second. Keyframe tolerance keeps decoding cheap: a
    /// dead stretch lasts many seconds, so half a second of slack changes nothing.
    private static func samples(of asset: AVAsset, duration: Double) async -> [TrimSample]? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 64, height: 64)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        let times = SmartTrimEngine.sampleTimes(duration: duration).map { CMTime(seconds: $0, preferredTimescale: 600) }
        var samples: [TrimSample] = []
        samples.reserveCapacity(times.count)
        for await result in generator.images(for: times) {
            if Task.isCancelled { return nil }
            guard let image = try? result.image else { continue }
            if let stats = autoreleasepool(invoking: { AccidentalShotEngine.stats(image) }) {
                let time = (try? result.actualTime.seconds) ?? result.requestedTime.seconds
                samples.append(TrimSample(time: time, stats: stats))
            }
        }
        // Too few frames decoded to judge (corrupt or unusual file): leave it alone.
        return samples.count >= max(3, times.count / 2) ? samples : nil
    }

    // MARK: - Trimming

    @concurrent
    func trim(_ candidate: TrimCandidate, progress: @escaping @Sendable (Double) -> Void) async throws -> TrimResult {
        guard !candidate.isAllDead, !candidate.keptRanges.isEmpty else { throw CompressionError.noSavings }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [candidate.id], options: nil).firstObject else {
            throw CompressionError.notFound
        }
        let originalBytes = candidate.item.byteSize ?? AssetSizeService.storageInfo(of: asset)?.bytes ?? 0
        let source = try await VideoCompressionService.avAsset(for: asset)
        let composition = try await Self.composition(of: source.asset, keeping: candidate.keptRanges)

        let output = FileManager.default.temporaryDirectory.appendingPathComponent("keeproll-trim-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: output) }
        // Passthrough copies the original's compressed data: no quality loss, and the copy
        // is the original minus the dead stretches. Highest quality is the fallback.
        try await VideoCompressionService.export(composition.asset,
                                                 presets: [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality],
                                                 to: output, progress: progress)
        try Task.checkCancellation()

        let newBytes = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard newBytes > 0 else { throw CompressionError.exportFailed("empty output") }
        guard newBytes < originalBytes else { throw TrimError.notSmaller }
        let newID = try await VideoCompressionService.saveCopy(of: output, like: asset)
        Log.photos.debug("Trimmed a video: \(candidate.deadSeconds, format: .fixed(precision: 1))s removed, \(originalBytes) → \(newBytes) bytes")
        return TrimResult(newAssetID: newID, originalBytes: originalBytes, newBytes: newBytes)
    }

    /// The kept stretches, back to back, with the original's orientation.
    private static func composition(of asset: AVAsset, keeping ranges: [TrimRange]) async throws -> VideoCompressionService.AssetBox {
        let composition = AVMutableComposition()
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let sourceVideo = videoTracks.first,
              let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CompressionError.exportFailed("no video track")
        }
        video.preferredTransform = try await sourceVideo.load(.preferredTransform)
        let audio = audioTracks.isEmpty ? nil : composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let assetDuration = try await asset.load(.duration)

        var cursor = CMTime.zero
        for range in ranges {
            let start = CMTime(seconds: range.start, preferredTimescale: 600)
            let end = CMTimeMinimum(CMTime(seconds: range.end, preferredTimescale: 600), assetDuration)
            guard end > start else { continue }
            let timeRange = CMTimeRange(start: start, end: end)
            try video.insertTimeRange(timeRange, of: sourceVideo, at: cursor)
            if let audio, let sourceAudio = audioTracks.first {
                try? audio.insertTimeRange(timeRange, of: sourceAudio, at: cursor)
            }
            cursor = cursor + timeRange.duration
        }
        guard cursor > .zero else { throw CompressionError.noSavings }
        return VideoCompressionService.AssetBox(asset: composition)
    }
}
