// Writes short colour-sweep videos for the simulator (xcrun simctl addmedia).
// Usage: swift scripts/make_video_fixtures.swift <outDir> <count>
import AVFoundation
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "KeeprollTests/Fixtures/Videos")
let count = args.count > 2 ? Int(args[2]) ?? 3 : 3
let width = 1280, height = 720, fps: Int32 = 30

func writeVideo(index: Int, seconds: Int) throws {
    let url = outDir.appendingPathComponent(String(format: "fixture-video-%02d.mp4", index))
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000 * (index + 1)],
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    let frames = seconds * Int(fps)
    for frame in 0..<frames {
        while !input.isReadyForMoreMediaData { usleep(2000) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        guard let buffer else { continue }
        CVPixelBufferLockBaseAddress(buffer, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
        let t = CGFloat(frame) / CGFloat(frames)
        ctx.setFillColor(CGColor(red: 0.2 + 0.5 * t, green: 0.3 + 0.2 * CGFloat(index), blue: 0.8 - 0.5 * t, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: 100 + t * CGFloat(width - 400), y: 200, width: 300, height: 300))
        // Noise so the encoder can't compress it to nothing.
        for _ in 0..<400 {
            ctx.setFillColor(CGColor(gray: CGFloat.random(in: 0...1), alpha: 0.5))
            ctx.fill(CGRect(x: CGFloat.random(in: 0...CGFloat(width)), y: CGFloat.random(in: 0...CGFloat(height)), width: 12, height: 12))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
    }
    input.markAsFinished()
    let group = DispatchGroup()
    group.enter()
    writer.finishWriting { group.leave() }
    group.wait()
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("wrote \(url.lastPathComponent) (\(size / 1_000_000) MB)")
}

for i in 0..<count { try writeVideo(index: i, seconds: 4 + i * 4) }
