import Photos
import SwiftUI
import UIKit

nonisolated protocol ThumbnailProviding: Sendable {
    /// `allowsNetwork`: fetch the full-quality version from the owner's iCloud when it
    /// isn't on the device. Only for single-photo views the user explicitly opened.
    func thumbnail(for id: String, targetSize: CGSize, allowsNetwork: Bool) async -> UIImage?
}

extension ThumbnailProviding {
    func thumbnail(for id: String, targetSize: CGSize) async -> UIImage? {
        await thumbnail(for: id, targetSize: targetSize, allowsNetwork: false)
    }
}

/// Loads thumbnails through one shared `PHCachingImageManager`.
///
/// Uses opportunistic delivery: with iCloud "Optimize Storage", the full-quality image
/// often isn't on the device, and a high-quality-only request with network off returns
/// nothing (the black squares seen on a real library). Opportunistic delivery hands
/// over the small local copy first, then the sharp one if it can be had; we keep the
/// best image that arrives.
///
/// `@unchecked Sendable`: its only stored property is the caching manager, and Apple
/// documents PHImageManager as safe to call from any thread.
nonisolated final class ThumbnailProvider: ThumbnailProviding, @unchecked Sendable {
    private let manager = PHCachingImageManager()

    func thumbnail(for id: String, targetSize: CGSize, allowsNetwork: Bool) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowsNetwork // grids never download (D7)

        let state = DeliveryState()
        return await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if let result = state.receive(image, final: !degraded) {
                    continuation.resume(returning: result.image)
                }
            }
        }
    }
}

/// Collects opportunistic callbacks: keeps the latest image and reports once, on the
/// final callback (which may carry no image when the sharp copy is only in iCloud).
nonisolated final class DeliveryState: @unchecked Sendable {
    private let lock = NSLock()
    private var best: UIImage?
    private var finished = false

    /// Returns the image to deliver when the request is complete, else nil.
    func receive(_ image: UIImage?, final: Bool) -> (image: UIImage?, Void)? {
        lock.withLock {
            guard !finished else { return nil }
            if let image { best = image }
            guard final else { return nil }
            finished = true
            return (best, ())
        }
    }
}

/// Used when no provider is injected (for example in previews of isolated components).
nonisolated struct EmptyThumbnailProvider: ThumbnailProviding {
    func thumbnail(for id: String, targetSize: CGSize, allowsNetwork: Bool) async -> UIImage? { nil }
}

extension EnvironmentValues {
    @Entry var thumbnails: any ThumbnailProviding = EmptyThumbnailProvider()
}
