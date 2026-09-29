import CoreGraphics
import Foundation
import Vision

/// Runs Vision requests off the cooperative pool, on a few dedicated serial lanes with a
/// watchdog. Same lesson as `FeaturePrintService`: `VNImageRequestHandler.perform`
/// blocks its thread until Vision's own queue returns, and calling it from a task group
/// once parked every pool thread and deadlocked the scan. Shared by OCR and aesthetics.
///
/// `@unchecked Sendable`: `disabled` and `next` are guarded by `lock`.
nonisolated final class VisionRunner: @unchecked Sendable {
    private let lanes: [DispatchQueue]
    private let lock = NSLock()
    private var disabled = false
    private var next = 0
    private let timeout: TimeInterval
    private let name: String

    init(name: String, lanes: Int = 2, timeout: TimeInterval = 6) {
        self.name = name
        self.lanes = (0..<max(1, lanes)).map { DispatchQueue(label: "me.adithyan.shalinth.Sift.\(name).\($0)", qos: .userInitiated) }
        self.timeout = timeout
    }

    var isAvailable: Bool { lock.withLock { !disabled } }

    private func nextLane() -> DispatchQueue {
        lock.withLock {
            defer { next = (next + 1) % lanes.count }
            return lanes[next]
        }
    }

    /// Performs `requests` on `image` and hands the finished requests to `read` on the
    /// lane. Returns nil if Vision failed or timed out; a timeout disables the runner for
    /// the rest of the process so a wedged model can't stall every later scan.
    func perform<T: Sendable>(_ requests: [VNRequest], on image: CGImage, read: @escaping @Sendable ([VNRequest]) -> T?) async -> T? {
        guard isAvailable else { return nil }
        let box = RequestBox(requests: requests)
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce()
            nextLane().async {
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                let value: T? = (try? handler.perform(box.requests)) == nil ? nil : read(box.requests)
                if once.claim() { continuation.resume(returning: value) }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [self] in
                guard once.claim() else { return }
                lock.withLock { disabled = true }
                Log.scan.error("Vision \(self.name, privacy: .public) timed out; disabled for this run")
                continuation.resume(returning: nil)
            }
        }
    }

    /// VNRequest isn't Sendable; the array is handed to exactly one lane and never shared.
    private struct RequestBox: @unchecked Sendable { let requests: [VNRequest] }
}
