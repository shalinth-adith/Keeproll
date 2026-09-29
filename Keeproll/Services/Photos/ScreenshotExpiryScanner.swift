import Photos
import Vision

/// Finds screenshots whose content has expired (bonus: smart categories).
nonisolated protocol ScreenshotExpiryScanning: Sendable {
    func findExpired() async -> [ExpiredScreenshot]
}

/// Runs on-device OCR over each screenshot once, caches the verdict, and returns the
/// expired ones, most recently expired first. Text never leaves the device and is never
/// stored: only the kind, the dates and a confidence are cached.
nonisolated final class ScreenshotExpiryScanner: ScreenshotExpiryScanning {
    private let photos: PhotoLibraryProviding
    private let cache: ScanCache
    private let runner = VisionRunner(name: "ocr", lanes: 2, timeout: 8)
    /// Verdicts below this are dropped rather than shown as "possible".
    static let minimumConfidence: Float = 0.6

    init(photos: PhotoLibraryProviding, cache: ScanCache) {
        self.photos = photos
        self.cache = cache
    }

    private struct AssetBox: @unchecked Sendable { let asset: PHAsset }

    @concurrent
    func findExpired() async -> [ExpiredScreenshot] {
        let signpost = Signposts.scan.beginInterval("scan.expired")
        defer { Signposts.scan.endInterval("scan.expired", signpost) }
        let started = Date()
        let now = Date()
        let items = await photos.fetchScreenshots()
        guard !items.isEmpty else { return [] }
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var assets: [PHAsset] = []
        PHAsset.fetchAssets(withLocalIdentifiers: items.map(\.id), options: nil).enumerateObjects { asset, _, _ in assets.append(asset) }

        var found: [ExpiredScreenshot] = []
        var ocrRuns = 0
        let width = max(2, ProcessInfo.processInfo.activeProcessorCount)
        await withTaskGroup(of: (ExpiredScreenshot?, Bool).self) { group in
            var next = 0
            func start() {
                guard next < assets.count else { return }
                let box = AssetBox(asset: assets[next])
                next += 1
                guard let item = byID[box.asset.localIdentifier] else { return }
                group.addTask { await self.evaluate(box, item: item, now: now) }
            }
            for _ in 0..<width { start() }
            for await (entry, ran) in group {
                if Task.isCancelled { group.cancelAll(); return }
                if ran { ocrRuns += 1 }
                if let entry { found.append(entry) }
                start()
            }
        }
        guard !Task.isCancelled else { return [] }
        await cache.save()
        Log.perf.info("Expiry scan: \(items.count) screenshots, \(found.count) expired, \(ocrRuns) OCR runs, \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s")
        return found.sorted { $0.verdict.expiresAt > $1.verdict.expiresAt }
    }

    private func evaluate(_ box: AssetBox, item: MediaItem, now: Date) async -> (ExpiredScreenshot?, Bool) {
        guard !item.isFavorite, let captured = item.creationDate else { return (nil, false) }
        if let cached = await cache.expiry(for: item.id, modified: item.modificationDate) {
            guard let kind = cached.kind else { return (nil, false) }
            let verdict = ExpiryVerdict(kind: kind, expiresAt: Date(timeIntervalSinceReferenceDate: cached.expiresAt),
                                        mentionedDate: cached.mentionedDate == 0 ? nil : Date(timeIntervalSinceReferenceDate: cached.mentionedDate),
                                        confidence: cached.confidence)
            return (Self.shown(verdict, now: now) ? ExpiredScreenshot(item: item, verdict: verdict) : nil, false)
        }
        guard let image = await AssetThumbnailLoader.image(for: box.asset, side: 1024) else { return (nil, false) }
        guard let text = await recognizeText(image) else { return (nil, true) } // Vision unavailable: try again next scan
        let verdict = ScreenshotExpiryEngine.verdict(text: text, capturedOn: captured, now: now)
        await cache.store(ScanCache.ExpiryRecord(
            modified: item.modificationDate?.timeIntervalSinceReferenceDate ?? 0,
            kind: verdict?.kind,
            expiresAt: verdict?.expiresAt.timeIntervalSinceReferenceDate ?? 0,
            mentionedDate: verdict?.mentionedDate?.timeIntervalSinceReferenceDate ?? 0,
            confidence: verdict?.confidence ?? 0
        ), for: item.id)
        guard let verdict, Self.shown(verdict, now: now) else { return (nil, true) }
        return (ExpiredScreenshot(item: item, verdict: verdict), true)
    }

    private static func shown(_ verdict: ExpiryVerdict, now: Date) -> Bool {
        verdict.confidence >= minimumConfidence && verdict.expiresAt < now
    }

    /// All recognised lines joined with newlines. Fast recognition is enough for keywords
    /// and dates; language correction is off so codes aren't "corrected" into words.
    private func recognizeText(_ image: CGImage) async -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        return await runner.perform([request], on: image) { requests in
            guard let request = requests.first as? VNRecognizeTextRequest, let results = request.results else { return nil }
            return results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }
    }
}
