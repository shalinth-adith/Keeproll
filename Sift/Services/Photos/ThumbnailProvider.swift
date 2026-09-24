import Photos
import SwiftUI
import UIKit

nonisolated protocol ThumbnailProviding: Sendable {
    func thumbnail(for id: String, targetSize: CGSize) async -> UIImage?
}

/// Loads thumbnails through one shared `PHCachingImageManager`.
///
/// `@unchecked Sendable`: its only stored property is the caching manager, and Apple
/// documents PHImageManager as safe to call from any thread.
nonisolated final class ThumbnailProvider: ThumbnailProviding, @unchecked Sendable {
    private let manager = PHCachingImageManager()

    func thumbnail(for id: String, targetSize: CGSize) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat // exactly one callback
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false // never download from iCloud (D7)

        return await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

/// Used when no provider is injected (for example in previews of isolated components).
nonisolated struct EmptyThumbnailProvider: ThumbnailProviding {
    func thumbnail(for id: String, targetSize: CGSize) async -> UIImage? { nil }
}

extension EnvironmentValues {
    @Entry var thumbnails: any ThumbnailProviding = EmptyThumbnailProvider()
}
