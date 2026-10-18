import AVFoundation
import Photos

nonisolated protocol SmartTrimScanning: Sendable {
    /// Videos with dead stretches, biggest saving first.
    func findCandidates() async -> [TrimCandidate]
    /// Which of these asset ids are still in the library (for trimmed originals waiting
    /// on Review, QA T2).
    func existingIDs(_ ids: [String]) async -> Set<String>
}

nonisolated struct TrimResult: Sendable, Equatable {
    let newAssetID: String
    let originalBytes: Int64
    let newBytes: Int64
    var savedBytes: Int64 { max(originalBytes - newBytes, 0) }
}

nonisolated enum TrimError: LocalizedError, Equatable {
    case notSmaller
    case unsupported

    var errorDescription: String? {
        switch self {
        case .notSmaller:
            String(localized: "The trimmed copy wouldn't be much smaller, because the dark parts take almost no space. Nothing was changed.")
        case .unsupported:
            String(localized: "This video has extra tracks (Cinematic, slow motion or spatial) that a trimmed copy can't keep. Nothing was changed.")
        }
    }
}

nonisolated protocol VideoTrimming: Sendable {
    func trim(_ candidate: TrimCandidate, progress: @escaping @Sendable (Double) -> Void) async throws -> TrimResult
}

/// Smart Trim (bonus): finds the dark, silent stretches of videos and saves a copy
/// without them.
///
/// Scanning samples about one frame a second at 64 px and the sound level of every
/// second, from local videos only (D7: no iCloud downloads), and caches the result per
/// video, so each clip is analysed once. Trimming follows the compression pattern: the
/// trimmed copy is added to the library first, the original only goes to Review (D10).
///
/// Videos whose extra content a copy can't carry (Cinematic depth, slow motion, spatial
/// video, more than one video track) are never offered (QA T1).
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

    @concurrent
    func existingIDs(_ ids: [String]) async -> Set<String> {
        guard !ids.isEmpty else { return [] }
        var found = Set<String>()
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            found.insert(asset.localIdentifier)
        }
        return found
    }

    /// Returns the candidate (if any) and whether the video was actually analysed.
    private func evaluate(_ item: MediaItem) async -> (TrimCandidate?, Bool) {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil).firstObject,
              !Self.hasUnsupportedSubtype(asset) else { return (nil, false) }
        if let cached = await cache.trim(for: item.id, modified: item.modificationDate) {
            return (Self.offered(TrimCandidate(item: item, deadRanges: cached.ranges, deadBytes: cached.deadBytes)), false)
        }
        guard let box = try? await VideoCompressionService.avAsset(for: asset, allowsNetwork: false) else {
            return (nil, false) // not on this iPhone; try again next scan
        }
        // Cache "nothing to trim" for videos a copy couldn't carry, so they're checked once.
        guard await Self.tracksAreSupported(box.asset) else {
            await cache.store(trim: [], for: item.id, modified: item.modificationDate)
            return (nil, true)
        }
        // The asset's own timeline, not PhotoKit's duration: they can differ (QA review).
        let duration = (try? await box.asset.load(.duration).seconds) ?? item.duration ?? 0
        guard let loud = await Self.loudSeconds(of: box.asset),
              let samples = await Self.samples(of: box.asset, duration: duration, loudSeconds: loud) else {
            return (nil, true)
        }
        let ranges = SmartTrimEngine.deadRanges(samples: samples, duration: duration)
        let deadBytes = ranges.isEmpty ? nil : await Self.compressedBytes(of: box.asset, in: ranges)
        // An interrupted measurement must not be cached as "not measured" (QA T8).
        guard !Task.isCancelled else { return (nil, true) }
        await cache.store(trim: ranges, deadBytes: deadBytes, for: item.id, modified: item.modificationDate)
        return (Self.offered(TrimCandidate(item: item, deadRanges: ranges, deadBytes: deadBytes)), true)
    }

    private static func offered(_ candidate: TrimCandidate) -> TrimCandidate? {
        !candidate.deadRanges.isEmpty && candidate.isWorthOffering ? candidate : nil
    }

    /// Cinematic, slow-motion and spatial videos carry content a plain copy drops.
    static func hasUnsupportedSubtype(_ asset: PHAsset) -> Bool {
        var unsupported: PHAssetMediaSubtype = [.videoHighFrameRate, .videoCinematic]
        if #available(iOS 18, *) { unsupported.insert(.spatialMedia) }
        return !asset.mediaSubtypes.isDisjoint(with: unsupported)
    }

    /// Exactly one video track. Any number of audio and metadata tracks is fine: they are
    /// all copied. Other track types (depth, subtitles, auxiliary video) are not.
    private static func tracksAreSupported(_ asset: AVAsset) async -> Bool {
        guard let tracks = try? await asset.load(.tracks) else { return false }
        let video = tracks.filter { $0.mediaType == .video }.count
        let other = tracks.filter { ![.video, .audio, .metadata].contains($0.mediaType) }.count
        return video == 1 && other == 0
    }

    /// Seconds with speech-level sound, from the first audio track decoded to 8 kHz mono.
    /// No audio track means silence everywhere. nil if the audio couldn't be read.
    private static func loudSeconds(of asset: AVAsset) async -> Set<Int>? {
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio) else { return nil }
        guard let track = tracks.first else { return [] }
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let rate = 8_000.0
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1, AVSampleRateKey: rate,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        var sums: [Int: (Double, Int)] = [:] // second → (sum of squares, count)
        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); return nil }
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let length = CMBlockBufferGetDataLength(block)
            var values = [Int16](repeating: 0, count: length / 2)
            let copied = values.withUnsafeMutableBytes { buffer in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: buffer.count, destination: buffer.baseAddress!)
            }
            guard copied == kCMBlockBufferNoErr else { continue }
            for (index, value) in values.enumerated() {
                let second = Int(start + Double(index) / rate)
                let v = Double(value) / 32_768
                let entry = sums[second, default: (0, 0)]
                sums[second] = (entry.0 + v * v, entry.1 + 1)
            }
        }
        guard reader.status == .completed else { return nil }
        let threshold = Double(SmartTrimEngine.soundThreshold)
        return Set(sums.compactMap { second, entry in
            guard entry.1 > 0 else { return nil }
            let rms = (entry.0 / Double(entry.1)).squareRoot()
            let decibels = rms > 0 ? 20 * log10(rms) : -160
            return decibels > threshold ? second : nil
        })
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
    private static func samples(of asset: AVAsset, duration: Double, loudSeconds: Set<Int>) async -> [TrimSample]? {
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
                // A sample stands for the time around it: sound a second either side counts.
                let second = Int(time)
                let heard = loudSeconds.contains(second) || loudSeconds.contains(second - 1) || loudSeconds.contains(second + 1)
                samples.append(TrimSample(time: time, stats: stats, hasSound: heard))
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
        guard !Self.hasUnsupportedSubtype(asset) else { throw TrimError.unsupported }
        let originalBytes = candidate.item.byteSize ?? AssetSizeService.storageInfo(of: asset)?.bytes ?? 0
        let source = try await VideoCompressionService.avAsset(for: asset)
        guard await Self.tracksAreSupported(source.asset) else { throw TrimError.unsupported }
        let composition = try await Self.composition(of: source.asset, keeping: candidate.keptRanges)
        // Make, model, location and the original's dates travel with the copy (QA T1).
        let metadata = (try? await source.asset.load(.metadata)) ?? []

        let output = FileManager.default.temporaryDirectory.appendingPathComponent("keeproll-trim-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: output) }
        // Passthrough copies the original's compressed data: no quality loss, and the copy
        // is the original minus the dead stretches. If passthrough fails, re-encode at the
        // highest quality instead (QA T6).
        do {
            try await VideoCompressionService.export(composition.asset, presets: [AVAssetExportPresetPassthrough],
                                                     metadata: metadata, to: output, progress: progress)
        } catch let error as CompressionError {
            try Task.checkCancellation()
            Log.photos.error("Passthrough trim failed, re-encoding: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: output)
            try await VideoCompressionService.export(composition.asset, presets: [AVAssetExportPresetHighestQuality],
                                                     metadata: metadata, to: output, progress: progress)
        }
        try Task.checkCancellation()

        let newBytes = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard newBytes > 0 else { throw CompressionError.exportFailed("empty output") }
        // The same 1 MB bar the list used to offer it (QA T6).
        guard originalBytes - newBytes >= SmartTrimEngine.minimumSavingBytes else { throw TrimError.notSmaller }
        let newID = try await VideoCompressionService.saveCopy(of: output, like: asset)
        Log.photos.debug("Trimmed a video: \(candidate.deadSeconds, format: .fixed(precision: 1))s removed, \(originalBytes) → \(newBytes) bytes")
        return TrimResult(newAssetID: newID, originalBytes: originalBytes, newBytes: newBytes)
    }

    /// The kept stretches, back to back: the video track with its orientation, and every
    /// audio and metadata track. A track that can't be copied fails the trim instead of
    /// silently going missing (QA T7).
    private static func composition(of asset: AVAsset, keeping ranges: [TrimRange]) async throws -> VideoCompressionService.AssetBox {
        let composition = AVMutableComposition()
        let tracks = try await asset.load(.tracks)
        guard let sourceVideo = tracks.first(where: { $0.mediaType == .video }) else {
            throw CompressionError.exportFailed("no video track")
        }
        var pairs: [(source: AVAssetTrack, target: AVMutableCompositionTrack)] = []
        for track in [sourceVideo] + tracks.filter({ $0.mediaType == .audio || $0.mediaType == .metadata }) {
            guard let target = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw CompressionError.exportFailed("couldn't add a \(track.mediaType.rawValue) track")
            }
            if track.mediaType == .video { target.preferredTransform = try await track.load(.preferredTransform) }
            pairs.append((track, target))
        }
        let assetDuration = try await asset.load(.duration)

        var cursor = CMTime.zero
        for range in ranges {
            let start = CMTime(seconds: range.start, preferredTimescale: 600)
            let end = CMTimeMinimum(CMTime(seconds: range.end, preferredTimescale: 600), assetDuration)
            guard end > start else { continue }
            let timeRange = CMTimeRange(start: start, end: end)
            for pair in pairs {
                let available = try await pair.source.load(.timeRange)
                let clipped = timeRange.intersection(available)
                guard clipped.duration > .zero else { continue } // e.g. audio that ends early
                try pair.target.insertTimeRange(clipped, of: pair.source, at: cursor + (clipped.start - timeRange.start))
            }
            cursor = cursor + timeRange.duration
        }
        guard cursor > .zero else { throw CompressionError.noSavings }
        return VideoCompressionService.AssetBox(asset: composition)
    }
}
