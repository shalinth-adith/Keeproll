import Photos
import UIKit

/// The local thumbnail used by every analysis: PhotoKit's cached fast copy first, then a
/// local full-quality decode. Never from iCloud (D7). Shared by the similarity scan,
/// OCR and aesthetics so they all see the same pixels.
nonisolated enum AssetThumbnailLoader {
    static func image(for asset: PHAsset, side: CGFloat) async -> CGImage? {
        if let fast = await request(asset, side: side, mode: .fastFormat) { return fast }
        return await request(asset, side: side, mode: .highQualityFormat)
    }

    private static func request(_ asset: PHAsset, side: CGFloat, mode: PHImageRequestOptionsDeliveryMode) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = mode
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side),
                                                  contentMode: .aspectFit, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
        return image?.cgImage
    }
}
