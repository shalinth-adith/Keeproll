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
}

nonisolated struct VaultImportResult: Sendable, Equatable {
    var imported: [VaultItem] = []
    /// Library assets that now have a copy in the vault (their originals go to Review).
    var copiedAssets: [(id: String, bytes: Int64)] = []
    var failed = 0

    static func == (a: VaultImportResult, b: VaultImportResult) -> Bool {
        a.imported == b.imported && a.failed == b.failed && a.copiedAssets.map(\.id) == b.copiedAssets.map(\.id)
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
/// can't be read while the iPhone is locked. They never leave the device. Importing only
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
            if let item = await copy(asset) {
                result.imported.append(item)
                result.copiedAssets.append((asset.localIdentifier, AssetSizeService.storageInfo(of: asset)?.bytes ?? item.bytes))
            } else {
                result.failed += 1
            }
        }
        progress(assets.count, assets.count)
        var all = loadIndex()
        all.append(contentsOf: result.imported)
        saveIndex(all)
        Log.photos.debug("Vault: imported \(result.imported.count), failed \(result.failed)")
        return result
    }

    func saveToPhotos(_ item: VaultItem) async throws {
        let url = fileURL(for: item)
        let type: PHAssetResourceType = item.kind == .video ? .video : .photo
        let date = item.creationDate
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false
            request.addResource(with: type, fileURL: url, options: options)
            request.creationDate = date
        }
    }

    /// Permanently removes items from the vault (the UI confirms first).
    func remove(_ items: [VaultItem]) {
        let ids = Set(items.map(\.id))
        for item in items {
            try? FileManager.default.removeItem(at: fileURL(for: item))
            try? FileManager.default.removeItem(at: thumbnailURL(for: item))
        }
        saveIndex(loadIndex().filter { !ids.contains($0.id) })
    }

    // MARK: - Private

    private func copy(_ asset: PHAsset) async -> VaultItem? {
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
        let bytes = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return VaultItem(id: id, kind: isVideo ? .video : .photo, fileName: fileName, thumbnailName: thumbName,
                         creationDate: asset.creationDate, addedAt: Date(), bytes: bytes,
                         duration: isVideo ? asset.duration : nil)
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

    private func saveIndex(_ items: [VaultItem]) {
        index = items
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: [.atomic, .completeFileProtection])
    }
}
