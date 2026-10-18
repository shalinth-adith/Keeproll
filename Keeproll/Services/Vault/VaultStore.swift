import Photos
import UIKit

nonisolated struct VaultItem: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case photo, video }

    let id: UUID
    let kind: Kind
    let fileName: String
    let thumbnailName: String
    let creationDate: Date?
    let addedAt: Date
    let bytes: Int64
    let duration: TimeInterval?
    /// The motion clip of a Live Photo, so it comes back as a Live Photo (QA M3).
    /// Optional, so indexes written by older builds still decode.
    var pairedFileName: String? = nil
}

nonisolated struct VaultImportResult: Sendable, Equatable {
    var imported: [VaultItem] = []
    /// Library assets that now have a copy in the vault (their originals go to Review).
    var copiedAssets: [(id: String, bytes: Int64)] = []
    /// Copied, but the original stays in the library (not queued for removal) because
    /// the vault can't hold all of it: RAW pairs and edit history (QA M3).
    var keptInLibrary = 0
    var failed = 0

    static func == (a: VaultImportResult, b: VaultImportResult) -> Bool {
        a.imported == b.imported && a.failed == b.failed && a.keptInLibrary == b.keptInLibrary
            && a.copiedAssets.map(\.id) == b.copiedAssets.map(\.id)
    }
}

nonisolated protocol VaultStoring: Sendable {
    func items() async -> [VaultItem]
    func importAssets(_ ids: [String], progress: @escaping @Sendable (Int, Int) -> Void) async -> VaultImportResult
    func fileURL(for item: VaultItem) -> URL
    func thumbnailURL(for item: VaultItem) -> URL
    func saveToPhotos(_ item: VaultItem) async throws
    func remove(_ items: [VaultItem]) async
}

/// The private vault's storage (bonus: PIN or Face ID protected vault).
///
/// Copies live in `Application Support/Vault` with `.complete` file protection, so they
/// can't be read while the iPhone is locked. Keeproll never uploads them, but like all app data
/// they are included in iCloud and computer backups (the UI says so). Importing only
/// *copies*: the library originals are handed back to the caller, which puts them in the
/// cart, so they are removed from the library on Review like everything else (D10).
actor VaultStore: VaultStoring {
    private let directory: URL
    private var index: [VaultItem]?

    init(directory: URL = VaultStore.defaultDirectory) {
        self.directory = directory
    }

    nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Vault")
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    func items() -> [VaultItem] {
        loadIndex().sorted { $0.addedAt > $1.addedAt }
    }

    nonisolated func fileURL(for item: VaultItem) -> URL { directory.appendingPathComponent(item.fileName) }
    nonisolated func thumbnailURL(for item: VaultItem) -> URL { directory.appendingPathComponent(item.thumbnailName) }

    func importAssets(_ ids: [String], progress: @escaping @Sendable (Int, Int) -> Void) async -> VaultImportResult {
        var result = VaultImportResult()
        do {
            try prepareDirectory()
        } catch {
            Log.photos.error("Vault directory failed: \(error.localizedDescription, privacy: .public)")
            result.failed = ids.count
            return result
        }
        var assets: [PHAsset] = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in assets.append(asset) }
        result.failed = ids.count - assets.count

        for (offset, asset) in assets.enumerated() {
            progress(offset, assets.count)
            if let copied = await copy(asset) {
                result.imported.append(copied.item)
                if copied.isComplete {
                    result.copiedAssets.append((asset.localIdentifier, AssetSizeService.storageInfo(of: asset)?.bytes ?? copied.item.bytes))
                } else {
                    result.keptInLibrary += 1
                }
            } else {
                result.failed += 1
            }
        }
        progress(assets.count, assets.count)
        var all = loadIndex()
        all.append(contentsOf: result.imported)
        do {
            try saveIndex(all)
        } catch {
            // Without an index entry the copies would be invisible, and their originals
            // would still be queued for removal. Roll the whole import back (QA M4).
            Log.photos.error("Vault index write failed: \(error.localizedDescription, privacy: .public)")
            for item in result.imported { deleteFiles(of: item) }
            index = nil
            return VaultImportResult(failed: ids.count)
        }
        Log.photos.debug("Vault: imported \(result.imported.count), kept \(result.keptInLibrary), failed \(result.failed)")
        return result
    }

    func saveToPhotos(_ item: VaultItem) async throws {
        let url = fileURL(for: item)
        let type: PHAssetResourceType = item.kind == .video ? .video : .photo
        let pairedURL = item.pairedFileName.map { directory.appendingPathComponent($0) }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        let date = item.creationDate
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false
            request.addResource(with: type, fileURL: url, options: options)
            if let pairedURL {
                // Photo + paired clip = a Live Photo again.
                request.addResource(with: .pairedVideo, fileURL: pairedURL, options: options)
            }
            request.creationDate = date
        }
    }

    /// Permanently removes items from the vault (the UI confirms first).
    /// An item leaves the index only once its files are really gone, so a failed delete
    /// never leaves an invisible file behind (QA L10).
    func remove(_ items: [VaultItem]) {
        let gone = Set(items.filter { deleteFiles(of: $0) }.map(\.id))
        guard !gone.isEmpty else { return }
        do {
            try saveIndex(loadIndex().filter { !gone.contains($0.id) })
        } catch {
            Log.photos.error("Vault index write failed on remove: \(error.localizedDescription, privacy: .public)")
            index = nil
        }
    }

    // MARK: - Private

    /// Copies one asset. `isComplete` is false when the vault copy can't stand in for
    /// the original (RAW pairs, edit history, a Live Photo whose clip couldn't be copied),
    /// so the caller leaves that original in the library.
    private func copy(_ asset: PHAsset) async -> (item: VaultItem, isComplete: Bool)? {
        let resources = PHAssetResource.assetResources(for: asset)
        let isVideo = asset.mediaType == .video
        // The edited version if there is one, else the original.
        let preferred: [PHAssetResourceType] = isVideo ? [.fullSizeVideo, .video] : [.fullSizePhoto, .photo]
        guard let resource = preferred.lazy.compactMap({ type in resources.first { $0.type == type } }).first else { return nil }

        let id = UUID()
        let ext = (resource.originalFilename as NSString).pathExtension.lowercased()
        let fileName = "\(id.uuidString).\(ext.isEmpty ? (isVideo ? "mov" : "jpg") : ext)"
        let thumbName = "\(id.uuidString)-thumb.jpg"
        let fileURL = directory.appendingPathComponent(fileName)

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true // the user chose these; the original may be in iCloud
        do {
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: fileURL, options: options)
            try protect(fileURL)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        if let thumb = await Self.thumbnail(for: asset), let data = thumb.jpegData(compressionQuality: 0.8) {
            let thumbURL = directory.appendingPathComponent(thumbName)
            try? data.write(to: thumbURL, options: [.atomic, .completeFileProtection])
        }
        var isComplete = !Self.hasExtraOriginals(resources)
        var pairedName: String?
        if !isVideo, asset.mediaSubtypes.contains(.photoLive) {
            let pairedTypes: [PHAssetResourceType] = [.fullSizePairedVideo, .pairedVideo]
            if let paired = pairedTypes.lazy.compactMap({ type in resources.first { $0.type == type } }).first {
                let name = "\(id.uuidString)-live.mov"
                let pairedURL = directory.appendingPathComponent(name)
                do {
                    try await PHAssetResourceManager.default().writeData(for: paired, toFile: pairedURL, options: options)
                    try protect(pairedURL)
                    pairedName = name
                } catch {
                    try? FileManager.default.removeItem(at: pairedURL)
                    isComplete = false
                }
            } else {
                isComplete = false
            }
        }
        let size = { (url: URL) in (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0 }
        let bytes = size(fileURL) + (pairedName.map { size(directory.appendingPathComponent($0)) } ?? 0)
        let item = VaultItem(id: id, kind: isVideo ? .video : .photo, fileName: fileName, thumbnailName: thumbName,
                             creationDate: asset.creationDate, addedAt: Date(), bytes: bytes,
                             duration: isVideo ? asset.duration : nil, pairedFileName: pairedName)
        return (item, isComplete)
    }

    /// True when the asset has data the vault doesn't keep: a RAW file alongside the
    /// JPEG, or edits (the vault keeps only the rendered result).
    nonisolated static func hasExtraOriginals(_ resources: [PHAssetResource]) -> Bool {
        hasExtraOriginals(types: resources.map(\.type))
    }

    nonisolated static func hasExtraOriginals(types: [PHAssetResourceType]) -> Bool {
        types.contains { [.alternatePhoto, .adjustmentData, .adjustmentBasePhoto, .adjustmentBaseVideo,
                          .adjustmentBasePairedVideo].contains($0) }
    }

    /// Deletes an item's files. True if none of them are left on disk.
    @discardableResult
    private func deleteFiles(of item: VaultItem) -> Bool {
        var urls = [fileURL(for: item), thumbnailURL(for: item)]
        if let paired = item.pairedFileName { urls.append(directory.appendingPathComponent(paired)) }
        var allGone = true
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.removeItem(at: url) } catch { allGone = false }
        }
        return allGone
    }

    private static func thumbnail(for asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 400, height: 400),
                                                  contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
    }

    private func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }

    private func loadIndex() -> [VaultItem] {
        if let index { return index }
        let loaded = (try? Data(contentsOf: indexURL)).flatMap { try? JSONDecoder().decode([VaultItem].self, from: $0) } ?? []
        index = loaded
        return loaded
    }

    /// Throws so callers can roll back (QA M4). `completeUnlessOpen` lets the write
    /// finish if the iPhone locks during a long import; the copies themselves stay `complete`.
    private func saveIndex(_ items: [VaultItem]) throws {
        let data = try JSONEncoder().encode(items)
        try data.write(to: indexURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        index = items
    }
}
