import Accelerate
import CoreGraphics
import Vision

/// Per-photo fingerprints computed from a small thumbnail. Pure functions of the image.
nonisolated enum ImageAnalysis {
    /// Renders `image` into an 8-bit grayscale buffer of the given size.
    static func grayscale(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    /// 64-bit difference hash: shrink to 9×8 grayscale, set a bit where a pixel is
    /// brighter than its right-hand neighbour. Robust to resizing and re-compression,
    /// so re-saved copies land within a few bits of each other.
    static func dHash(_ image: CGImage) -> UInt64? {
        guard let pixels = grayscale(image, width: 9, height: 8) else { return nil }
        var hash: UInt64 = 0
        for row in 0..<8 {
            for col in 0..<8 {
                hash <<= 1
                if pixels[row * 9 + col] > pixels[row * 9 + col + 1] { hash |= 1 }
            }
        }
        return hash
    }

    static func hamming(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }

    /// Variance of the Laplacian on a grayscale copy scaled to `maxSide` on its long edge.
    /// Sharp photos have strong edges (high variance); blurry ones don't. Always measured
    /// at the same size, so scores compare across photos whatever size PhotoKit returned.
    static func sharpness(_ image: CGImage, maxSide: Int = 160) -> Float {
        let scale = Double(maxSide) / Double(max(image.width, image.height))
        let width = max(3, Int(Double(image.width) * scale))
        let height = max(3, Int(Double(image.height) * scale))
        guard let pixels = grayscale(image, width: width, height: height) else { return 0 }
        return laplacianVariance(pixels, width: width, height: height)
    }

    static func laplacianVariance(_ pixels: [UInt8], width: Int, height: Int) -> Float {
        guard width >= 3, height >= 3 else { return 0 }
        var sum = 0.0, sumSquares = 0.0
        var count = 0.0
        for y in 1..<(height - 1) {
            let row = y * width
            for x in 1..<(width - 1) {
                let center = Int(pixels[row + x]) * 4
                let neighbours = Int(pixels[row + x - 1]) + Int(pixels[row + x + 1])
                    + Int(pixels[row - width + x]) + Int(pixels[row + width + x])
                let value = Double(center - neighbours)
                sum += value
                sumSquares += value * value
                count += 1
            }
        }
        let mean = sum / count
        return Float(sumSquares / count - mean * mean)
    }
}

/// Runs Vision feature prints off Swift's cooperative thread pool.
///
/// `VNImageRequestHandler.perform` blocks its thread until Vision's own queue finishes.
/// Called from the task group, every cooperative-pool thread ended up parked in
/// `dispatchGroupWait` and the scan deadlocked. So requests run on a few dedicated
/// serial queues ("lanes"), never on the pool, and a watchdog gives up after `timeout`.
/// If Vision ever hangs, it's switched off for the rest of the process and the scan
/// falls back to dHash comparisons.
///
/// One lane made Vision the bottleneck on a real library (7,724 photos: 106 s of queued
/// Vision time in a 60 s scan); three lanes keep the Neural Engine busy.
///
/// `@unchecked Sendable`: the mutable state (`disabled`, `next`) is guarded by `lock`.
nonisolated final class FeaturePrintService: @unchecked Sendable {
    private let lanes: [DispatchQueue]
    private let lock = NSLock()
    private var disabled = false
    private var next = 0
    private var exec = 0.0
    private var count = 0
    private let timeout: TimeInterval

    /// Time spent inside Vision itself (not queued), for the calibration log.
    var execSeconds: Double { lock.withLock { exec } }
    var printCount: Int { lock.withLock { count } }

    init(lanes: Int = 3, timeout: TimeInterval = 4) {
        self.lanes = (0..<max(1, lanes)).map {
            DispatchQueue(label: "me.adithyan.shalinth.Sift.vision.\($0)", qos: .userInitiated)
        }
        self.timeout = timeout
    }

    private func nextLane() -> DispatchQueue {
        lock.withLock {
            defer { next = (next + 1) % lanes.count }
            return lanes[next]
        }
    }

    var isAvailable: Bool { lock.withLock { !disabled } }

    func featurePrint(for image: CGImage) async -> [Float]? {
        guard isAvailable else { return nil }
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce()
            nextLane().async { [self] in
                let started = Date()
                let print = FeaturePrinter.featurePrint(for: image)
                let elapsed = Date().timeIntervalSince(started)
                lock.withLock { exec += elapsed; count += 1 }
                if once.claim() { continuation.resume(returning: print) }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [self] in
                guard once.claim() else { return }
                lock.withLock { disabled = true }
                Log.scan.error("Vision feature print timed out; falling back to hash comparison")
                continuation.resume(returning: nil)
            }
        }
    }
}

/// Lets exactly one of two racing callbacks resume a continuation.
nonisolated final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.withLock {
            if done { return false }
            done = true
            return true
        }
    }
}

/// Vision feature prints, reduced to plain `[Float]` so they're Sendable and cacheable.
/// Call through `FeaturePrintService`, never directly from a task group.
nonisolated enum FeaturePrinter {
    static func featurePrint(for image: CGImage) -> [Float]? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first, observation.elementType == .float else { return nil }
        let count = observation.elementCount
        return observation.data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self).prefix(count))
        }
    }

    /// Euclidean distance, the same metric as `VNFeaturePrintObservation.computeDistance`.
    static func distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        return vDSP.distanceSquared(a, b).squareRoot()
    }
}
