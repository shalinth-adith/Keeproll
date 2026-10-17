import Photos

/// Finds Live Photos and converts them to stills (bonus: Live Photos to still).
nonisolated protocol LivePhotoScanning: Sendable {
    func findLivePhotos() async -> [LivePhotoCandidate]
}

nonisolated protocol LivePhotoConverting: Sendable {
    /// Saves a still copy of `item` with the original's date, place and favourite flag.
    /// Returns the new asset's id. Never touches the original.
    func convertToStill(_ item: MediaItem) async throws -> String
}

nonisolated enum LivePhotoError: LocalizedError, Equatable {
    case notFound, noStill, exportFailed(String), saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound: String(localized: "This Live Photo is no longer in your library.")
        case .noStill: String(localized: "The still image couldn't be read. Nothing was changed.")
        case .exportFailed: String(localized: "The still couldn't be exported. Nothing was changed.")
        case .saveFailed: String(localized: "The still couldn't be saved to your library. Nothing was changed.")
        }
    }
}

/// Safe by construction, like video compression: the still is *added* to the library
/// first; the caller puts the original in the cart, so it leaves only on Review (D10).
///
/// A Live Photo is a still (HEIC or JPEG) plus a ~1.5 s clip. The clip is usually two to
/// three times the still, so converting typically frees 60–70 % of the asset.
nonisolated final class LivePhotoService: LivePhotoScanning, LivePhotoConverting {
    private let sizes: AssetSizeService

    init(sizes: AssetSizeService) { self.sizes = sizes }

    private struct AssetBox: @unchecked Sendable { let asset: PHAsset } // immutable PhotoKit snapshot

    @concurrent
    func findLivePhotos() async -> [LivePhotoCandidate] {
        let signpost = Signposts.scan.beginInterval("scan.livePhotos")
        defer { Signposts.scan.endInterval("scan.livePhotos", signpost) }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var live: [PHAsset] = []
        // Filtered in code: PhotoKit evaluates `mediaSubtypes & …` predicates unreliably.
        result.enumerateObjects { asset, _, _ in
            if asset.mediaSubtypes.contains(.photoLive) { live.append(asset) }
        }
        guard !live.isEmpty else { return [] }

        let boxes = live.map(AssetBox.init)
        let found: [LivePhotoCandidate] = await withTaskGroup(of: LivePhotoCandidate?.self) { group in
            for box in boxes { group.addTask { Self.candidate(for: box.asset) } }
            var out: [LivePhotoCandidate] = []
            for await candidate in group { if let candidate { out.append(candidate) } }
            return out
        }
        let sized = await sizes.fillSizes(found.map(\.item))
        let sizedByID = Dictionary(sized.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let items = found.compactMap { entry -> LivePhotoCandidate? in
            guard let item = sizedByID[entry.id] else { return nil }
            return LivePhotoCandidate(item: item, videoBytes: entry.videoBytes)
        }
        .sorted { $0.videoBytes > $1.videoBytes }
        Log.photos.debug("Found \(items.count) Live Photos")
        return items
    }

    /// The paired clip's size, read the same undocumented-but-standard way as file sizes.
    static func candidate(for asset: PHAsset) -> LivePhotoCandidate? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let clip = resources.first(where: { $0.type == .pairedVideo }),
              let bytes = (clip.value(forKey: "fileSize") as? NSNumber)?.int64Value, bytes > 0 else { return nil }
        return LivePhotoCandidate(item: PhotoLibraryService.item(from: asset, kind: .photo), videoBytes: bytes)
    }

    @concurrent
    func convertToStill(_ item: MediaItem) async throws -> String {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil).firstObject else {
            throw LivePhotoError.notFound
        }
        let resources = PHAssetResource.assetResources(for: asset)
        // The full-size edited still if the user edited it, else the original still.
        guard let still = resources.first(where: { $0.type == .fullSizePhoto }) ?? resources.first(where: { $0.type == .photo }) else {
            throw LivePhotoError.noStill
        }
        let ext = (still.originalFilename as NSString).pathExtension.isEmpty ? "heic" : (still.originalFilename as NSString).pathExtension
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("keeproll-still-\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: file) }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true // an explicit user action on their own photo (D7)
        do {
            try await PHAssetResourceManager.default().writeData(for: still, toFile: file, options: options)
        } catch {
            throw LivePhotoError.exportFailed(error.localizedDescription)
        }
        return try await Self.saveStill(file, like: asset)
    }

    /// Adds the still with the original's date, place and favourite flag; returns its id.
    private static func saveStill(_ file: URL, like original: PHAsset) async throws -> String {
        let creationDate = original.creationDate
        let location = original.location
        let isFavorite = original.isFavorite
        let placeholder = PlaceholderBox()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .photo, fileURL: file, options: options) // photo only: no paired video
                request.creationDate = creationDate
                request.location = location
                request.isFavorite = isFavorite
                placeholder.id = request.placeholderForCreatedAsset?.localIdentifier
            }
        } catch {
            throw LivePhotoError.saveFailed(error.localizedDescription)
        }
        guard let id = placeholder.id else { throw LivePhotoError.saveFailed("no placeholder") }
        Log.photos.debug("Saved a still copy of a Live Photo")
        return id
    }

    /// Written once inside `performChanges`, read after it returns.
    private final class PlaceholderBox: @unchecked Sendable { var id: String? }
}
