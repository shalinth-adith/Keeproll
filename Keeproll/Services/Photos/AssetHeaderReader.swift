import ImageIO
import Photos

/// Answers "was this taken by a camera?" from the first kilobytes of the original file.
///
/// EXIF and TIFF tags live at the start of JPEG and HEIC files, so the reader streams
/// the resource, stops after `headerBytes`, and parses what it has with an incremental
/// `CGImageSource`. That costs a few KB of I/O per photo instead of the full file (a
/// 7,000-photo library would otherwise mean reading tens of gigabytes). Results are
/// cached by `ScanCache`, so it happens once per photo.
///
/// Never touches the network (D7): an original that is only in iCloud yields `nil`.
nonisolated enum AssetHeaderReader {
    static let headerBytes = 96 * 1024
    static let retryBytes = 512 * 1024

    /// true / false when the header was readable; nil when it wasn't (iCloud-only,
    /// unsupported format, or the metadata sits beyond the bytes read).
    static func hasCameraMetadata(_ asset: PHAsset) async -> Bool? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .photo }) ?? resources.first(where: { $0.type == .fullSizePhoto }) else { return nil }
        if let answer = await read(resource, limit: headerBytes).flatMap(cameraMetadata(in:)) { return answer }
        // HEIC sometimes places the metadata box after a large item; one bigger read.
        return await read(resource, limit: retryBytes).flatMap(cameraMetadata(in:))
    }

    /// Filename and type of the original, for `ProvenanceEngine`. No I/O.
    static func identity(of asset: PHAsset) -> (filename: String?, uti: String?) {
        let resources = PHAssetResource.assetResources(for: asset)
        let resource = resources.first(where: { $0.type == .photo }) ?? resources.first(where: { $0.type == .fullSizePhoto }) ?? resources.first
        return (resource?.originalFilename, resource?.uniformTypeIdentifier)
    }

    /// Streams up to `limit` bytes of `resource`, then cancels. Returns what arrived.
    private static func read(_ resource: PHAssetResource, limit: Int) async -> Data? {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false
        let sink = ByteSink(limit: limit)
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce()
            let manager = PHAssetResourceManager.default()
            let id = manager.requestData(for: resource, options: options) { chunk in
                // Enough header: stop the stream. A chunk arriving before the id is stored
                // just waits for the next one; completion resumes us either way.
                if sink.append(chunk), let id = sink.requestID { manager.cancelDataRequest(id) }
            } completionHandler: { _ in
                // Cancelled or complete: either way, whatever arrived is what we parse.
                if once.claim() { continuation.resume(returning: sink.bytes) }
            }
            sink.requestID = id
        }
    }

    /// Camera make, model, lens or exposure present in the properties ImageIO can parse
    /// from a partial file. nil when the partial data is too short to say.
    static func cameraMetadata(in data: Data) -> Bool? {
        guard !data.isEmpty else { return nil }
        let source = CGImageSourceCreateIncremental(nil)
        CGImageSourceUpdateData(source, data as CFData, false)
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           tiff[kCGImagePropertyTIFFMake] != nil || tiff[kCGImagePropertyTIFFModel] != nil {
            return true
        }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           exif[kCGImagePropertyExifLensModel] != nil || exif[kCGImagePropertyExifExposureTime] != nil
            || exif[kCGImagePropertyExifFNumber] != nil || exif[kCGImagePropertyExifISOSpeedRatings] != nil {
            return true
        }
        // Properties parsed (width/height at least) but no camera tags anywhere.
        return props[kCGImagePropertyPixelWidth] != nil ? false : nil
    }

    /// Collects streamed chunks up to a limit. `@unchecked Sendable`: guarded by `lock`.
    private final class ByteSink: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var id: PHAssetResourceDataRequestID?
        private let limit: Int
        init(limit: Int) { self.limit = limit; data.reserveCapacity(limit) }
        var requestID: PHAssetResourceDataRequestID? {
            get { lock.withLock { id } }
            set { lock.withLock { id = newValue } }
        }
        /// Returns true once the limit is reached (caller cancels the request).
        func append(_ chunk: Data) -> Bool {
            lock.withLock {
                if data.count < limit { data.append(chunk.prefix(limit - data.count)) }
                return data.count >= limit
            }
        }
        var bytes: Data? { lock.withLock { data.isEmpty ? nil : data } }
    }
}
