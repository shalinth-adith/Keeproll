import Photos
import SwiftUI
import UIKit

nonisolated protocol ThumbnailProviding: Sendable {
    /// `allowsNetwork`: fetch the full-quality version from the owner's iCloud when it
    /// isn't on the device. Only for single-photo views the user explicitly opened.
    func thumbnail(for id: String, targetSize: CGSize, allowsNetwork: Bool) async -> UIImage?
    /// An image already in memory, returned synchronously so revisited cells never flash.
    func cachedThumbnail(for id: String, targetSize: CGSize) -> UIImage?
    /// Starts loading thumbnails that are about to scroll into view.
    func prefetch(_ ids: [String], targetSize: CGSize)
}

nonisolated extension ThumbnailProviding {
    func thumbnail(for id: String, targetSize: CGSize) async -> UIImage? {
        await thumbnail(for: id, targetSize: targetSize, allowsNetwork: false)
    }
    func cachedThumbnail(for id: String, targetSize: CGSize) -> UIImage? { nil }
    func prefetch(_ ids: [String], targetSize: CGSize) {}
}

/// Loads thumbnails through one shared `PHCachingImageManager`, with two in-memory caches
/// so grids scroll without waiting:
/// - decoded images, keyed by id and size (scrolling back is instant);
/// - `PHAsset` lookups, so a cell doesn't hit the Photos database for its asset each time.
/// Upcoming cells are pre-warmed with `startCachingImages`.
///
/// Delivery is opportunistic: with iCloud "Optimize Storage" the full-quality image often
/// isn't on the device, and a high-quality-only request with network off returns nothing
/// (black squares on a real library). Opportunistic delivery hands over the local small
/// copy first, then the sharp one if it can be had.
///
/// `@unchecked Sendable`: PHCachingImageManager is documented thread-safe, NSCache is
/// thread-safe, and the prefetch set is guarded by `lock`.
nonisolated final class ThumbnailProvider: ThumbnailProviding, @unchecked Sendable {
    private let manager = PHCachingImageManager()
    private let images = NSCache<NSString, UIImage>()
    private let assets = NSCache<NSString, PHAsset>()
    private let lock = NSLock()
    private var prefetched = Set<String>()

    init() {
        images.totalCostLimit = 120 * 1024 * 1024 // decoded bytes, ~ a few hundred thumbnails
        assets.countLimit = 5_000
        manager.allowsCachingHighQualityImages = false
    }

    func cachedThumbnail(for id: String, targetSize: CGSize) -> UIImage? {
        images.object(forKey: Self.key(id, targetSize))
    }

    func thumbnail(for id: String, targetSize: CGSize, allowsNetwork: Bool) async -> UIImage? {
        let key = Self.key(id, targetSize)
        if let cached = images.object(forKey: key) { return cached }
        guard let asset = asset(for: id) else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowsNetwork // grids never download (D7)

        let state = DeliveryState()
        let image: UIImage? = await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if let result = state.receive(image, final: !degraded) {
                    continuation.resume(returning: result.image)
                }
            }
        }
        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            images.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    func prefetch(_ ids: [String], targetSize: CGSize) {
        let fresh: [String] = lock.withLock {
            let new = ids.filter { !prefetched.contains($0) }
            prefetched.formUnion(new)
            if prefetched.count > 4_000 { prefetched.removeAll() }
            return new
        }
        guard !fresh.isEmpty else { return }
        let assets = fresh.compactMap { asset(for: $0) }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        manager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: options)
    }

    private func asset(for id: String) -> PHAsset? {
        if let cached = assets.object(forKey: id as NSString) { return cached }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        assets.setObject(asset, forKey: id as NSString)
        return asset
    }

    private static func key(_ id: String, _ size: CGSize) -> NSString {
        "\(id)|\(Int(size.width))x\(Int(size.height))" as NSString
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
