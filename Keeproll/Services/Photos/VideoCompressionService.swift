import AVFoundation
import Photos

nonisolated struct CompressionResult: Sendable, Equatable {
    let newAssetID: String
    let originalBytes: Int64
    let newBytes: Int64
    var savedBytes: Int64 { max(originalBytes - newBytes, 0) }
}

nonisolated enum CompressionError: LocalizedError, Equatable {
    case notFound
    case noSavings
    case exportFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound: String(localized: "This video is no longer in your library.")
        case .noSavings: String(localized: "This video is already compact. A smaller copy wouldn't save much, so nothing was changed.")
        case .exportFailed: String(localized: "The video couldn't be compressed. Nothing was changed.")
        case .saveFailed: String(localized: "The smaller copy couldn't be saved to your library. Nothing was changed.")
        }
    }
}

nonisolated protocol VideoCompressing: Sendable {
    func compress(_ item: MediaItem, progress: @escaping @Sendable (Double) -> Void) async throws -> CompressionResult
}

/// Compresses a large video to HEVC (bonus: compress large videos).
///
/// Safe by construction: the smaller copy is *added* to the library (same date,
/// location and favourite flag), and the original is never touched here. The caller
/// puts the original in the cart, so it's only removed on Review (D10). If the copy
/// wouldn't save at least 10 %, nothing is saved at all.
nonisolated final class VideoCompressionService: VideoCompressing {
    /// Rough output rates for the chosen presets, used to decide whether compressing is
    /// worth offering: HEVC 1080p ≈ 5 Mbit/s, 720p ≈ 3 Mbit/s, plus audio.
    static func estimatedSize(for item: MediaItem) -> Int64? {
        guard let duration = item.duration, duration > 0, let original = item.byteSize else { return nil }
        let is1080OrMore = max(item.pixelWidth, item.pixelHeight) > 1280
        let bytesPerSecond: Double = is1080OrMore ? 650_000 : 400_000
        let estimate = Int64(duration * bytesPerSecond)
        return estimate < original ? estimate : nil
    }

    /// Worth offering: saves at least 20 MB and a quarter of the file.
    static func worthCompressing(_ item: MediaItem) -> Int64? {
        guard let original = item.byteSize, let estimate = estimatedSize(for: item) else { return nil }
        let saving = original - estimate
        return saving >= 20_000_000 && saving >= original / 4 ? saving : nil
    }

    @concurrent
    func compress(_ item: MediaItem, progress: @escaping @Sendable (Double) -> Void) async throws -> CompressionResult {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil).firstObject else {
            throw CompressionError.notFound
        }
        let originalBytes = item.byteSize ?? AssetSizeService.storageInfo(of: asset)?.bytes ?? 0
        let source = try await Self.avAsset(for: asset)

        let output = FileManager.default.temporaryDirectory.appendingPathComponent("keeproll-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: output) }
        try await Self.export(source.asset, to: output, progress: progress)
        // Closing the sheet cancels the task: never save a copy after that (QA M8).
        try Task.checkCancellation()

        let newBytes = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard newBytes > 0 else { throw CompressionError.exportFailed("empty output") }
        guard newBytes < originalBytes * 9 / 10 else { throw CompressionError.noSavings }

        let newID = try await Self.saveCopy(of: output, like: asset)
        Log.photos.debug("Compressed a video: \(originalBytes) → \(newBytes) bytes")
        return CompressionResult(newAssetID: newID, originalBytes: originalBytes, newBytes: newBytes)
    }

    // MARK: - Steps

    /// AVAsset is immutable once loaded; boxed to cross into the export task.
    struct AssetBox: @unchecked Sendable { let asset: AVAsset }

    /// Shared with Smart Trim. `allowsNetwork` is true only for an explicit user action
    /// on their own video (D7); scans never download.
    static func avAsset(for asset: PHAsset, allowsNetwork: Bool = true) async throws -> AssetBox {
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = allowsNetwork
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let avAsset {
                    continuation.resume(returning: AssetBox(asset: avAsset))
                } else {
                    let reason = (info?[PHImageErrorKey] as? Error)?.localizedDescription ?? "no asset"
                    continuation.resume(throwing: CompressionError.exportFailed(reason))
                }
            }
        }
    }

    /// Exports with the first preset that works (by default HEVC 1080p, else 720p H.264),
    /// reporting progress for the UI. Cancelling the task stops the export. Shared with Smart Trim.
    static func export(_ asset: AVAsset, presets: [String] = [AVAssetExportPresetHEVC1920x1080, AVAssetExportPreset1280x720],
                       metadata: [AVMetadataItem] = [],
                       to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let session = presets.lazy.compactMap({ AVAssetExportSession(asset: asset, presetName: $0) }).first else {
            throw CompressionError.exportFailed("no export session")
        }
        session.shouldOptimizeForNetworkUse = true
        if !metadata.isEmpty { session.metadata = metadata }
        if #unavailable(iOS 18) {
            session.outputURL = url
            session.outputFileType = .mov
        }

        let box = SessionBox(session: session)
        if #available(iOS 18, *) {
            // The async API stops the export when the task is cancelled (QA M8).
            let watcher = Task {
                for await state in box.session.states(updateInterval: 0.2) {
                    if case .exporting(let value) = state { progress(value.fractionCompleted) }
                }
            }
            defer { watcher.cancel() }
            do {
                try await box.session.export(to: url, as: .mov)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw CompressionError.exportFailed(error.localizedDescription)
            }
            progress(1)
            return
        }

        let poller = Task {
            while !Task.isCancelled {
                progress(Double(box.session.progress))
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { poller.cancel() }

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                box.session.exportAsynchronously { continuation.resume() }
            }
        } onCancel: {
            box.session.cancelExport()
        }
        if Task.isCancelled || box.session.status == .cancelled { throw CancellationError() }
        progress(1)
        guard box.session.status == .completed else {
            throw CompressionError.exportFailed(box.session.error?.localizedDescription ?? "status \(box.session.status.rawValue)")
        }
    }

    /// `AVAssetExportSession` is thread-safe for status/progress reads; boxed for the poller.
    private struct SessionBox: @unchecked Sendable { let session: AVAssetExportSession }

    /// Adds the file to the library with the original's date, place and favourite flag,
    /// and returns the new asset's id. Shared with Smart Trim.
    static func saveCopy(of file: URL, like original: PHAsset) async throws -> String {
        let creationDate = original.creationDate
        let location = original.location
        let isFavorite = original.isFavorite
        let placeholder = PlaceholderBox()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .video, fileURL: file, options: options)
                request.creationDate = creationDate
                request.location = location
                request.isFavorite = isFavorite
                placeholder.id = request.placeholderForCreatedAsset?.localIdentifier
            }
        } catch {
            throw CompressionError.saveFailed(error.localizedDescription)
        }
        guard let id = placeholder.id else { throw CompressionError.saveFailed("no placeholder") }
        return id
    }

    /// Written once inside `performChanges`, read after it returns.
    private final class PlaceholderBox: @unchecked Sendable { var id: String? }
}
