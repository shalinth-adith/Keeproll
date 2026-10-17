#if DEBUG
import AVFoundation
import CoreGraphics
import ImageIO
import Photos
import UniformTypeIdentifiers

/// `-KeeprollSeedLivePhotos` launch argument (simulator only in practice): creates three
/// real Live Photos in the library so the Live Photos screen can be checked. A Live
/// Photo is a still and a clip that share a content identifier (MakerApple tag 17 on
/// the JPEG, `com.apple.quicktime.content.identifier` on the MOV, plus a
/// still-image-time metadata track), which `simctl addmedia` can't produce from loose files.
nonisolated enum LivePhotoSeedFixtures {
    static func seedIfRequested() async {
        let key = "debug.livePhotosSeeded"
        guard ProcessInfo.processInfo.arguments.contains("-KeeprollSeedLivePhotos"),
              !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        for index in 0..<3 {
            do {
                let id = UUID().uuidString
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(id)")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let jpeg = dir.appendingPathComponent("IMG_\(9000 + index).JPG")
                let mov = dir.appendingPathComponent("IMG_\(9000 + index).MOV")
                try writeStill(to: jpeg, hue: CGFloat(index) / 3, identifier: id)
                try await writeClip(to: mov, hue: CGFloat(index) / 3, identifier: id, seconds: 2 + index)
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, fileURL: jpeg, options: nil)
                    request.addResource(with: .pairedVideo, fileURL: mov, options: nil)
                    request.creationDate = Date().addingTimeInterval(-Double(index) * 86_400 * 9)
                }
                try? FileManager.default.removeItem(at: dir)
            } catch {
                Log.photos.error("Live Photo seed failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func writeStill(to url: URL, hue: CGFloat, identifier: String) throws {
        let width = 3024, height = 4032
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(red: 0.9 - 0.4 * hue, green: 0.6, blue: 0.5 + 0.4 * hue, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0.15, green: 0.35, blue: 0.3, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: width / 4, y: height / 3, width: width / 2, height: width / 2))
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        let props: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: ["17": identifier],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 15"],
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    private static func writeClip(to url: URL, hue: CGFloat, identifier: String, seconds: Int) async throws {
        let width = 1440, height = 1920, fps: Int32 = 30
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let identifierItem = AVMutableMetadataItem()
        identifierItem.key = "com.apple.quicktime.content.identifier" as NSString
        identifierItem.keySpace = .quickTimeMetadata
        identifierItem.value = identifier as NSString
        identifierItem.dataType = kCMMetadataBaseDataType_UTF8 as String
        writer.metadata = [identifierItem]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)

        // Still-image-time track: tells Photos which frame is the still.
        let spec: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: kCMMetadataBaseDataType_SInt8 as String,
        ]
        var description: CMFormatDescription?
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed,
                                                                    metadataSpecifications: [spec] as CFArray, formatDescriptionOut: &description)
        let metadataInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: description)
        let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
        writer.add(metadataInput)
        input.mediaTimeScale = fps
        metadataInput.addTrackAssociation(withTrackOf: input, type: AVAssetTrack.AssociationType.metadataReferent.rawValue)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let stillItem = AVMutableMetadataItem()
        stillItem.key = "com.apple.quicktime.still-image-time" as NSString
        stillItem.keySpace = .quickTimeMetadata
        stillItem.value = 0 as NSNumber
        stillItem.dataType = kCMMetadataBaseDataType_SInt8 as String
        let group = AVTimedMetadataGroup(items: [stillItem], timeRange: CMTimeRange(start: CMTime(value: Int64(fps / 2), timescale: fps), duration: CMTime(value: 1, timescale: fps)))
        while !metadataInput.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
        metadataAdaptor.append(group)
        metadataInput.markAsFinished()

        let frames = seconds * Int(fps)
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, nil, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
                let t = CGFloat(frame) / CGFloat(frames)
                ctx.setFillColor(CGColor(red: 0.9 - 0.4 * hue, green: 0.6, blue: 0.5 + 0.4 * hue, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                ctx.setFillColor(CGColor(red: 0.15, green: 0.35, blue: 0.3, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: CGFloat(width) * (0.25 + 0.1 * t), y: CGFloat(height) / 3, width: CGFloat(width) / 2, height: CGFloat(width) / 2))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw LivePhotoError.exportFailed(writer.error?.localizedDescription ?? "writer") }
    }
}
#endif
