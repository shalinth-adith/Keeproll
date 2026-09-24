import AVFoundation
import Photos

nonisolated protocol VideoPlaybackProviding: Sendable {
    /// A player item for the asset. May stream from iCloud: this is an explicit user
    /// tap on a preview, so network use is allowed here (D7).
    func playerItem(for id: String) async -> AVPlayerItem?
}

nonisolated final class VideoPlaybackService: VideoPlaybackProviding {
    func playerItem(for id: String) async -> AVPlayerItem? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }
}

nonisolated struct NoVideoPlayback: VideoPlaybackProviding {
    func playerItem(for id: String) async -> AVPlayerItem? { nil }
}
