import CoreGraphics
import Vision

/// iOS 18's on-device aesthetics model, used only for its "utility image" flag: the
/// content is a screen, a document, a receipt or a forward rather than a memorable photo.
/// On iOS 17 every answer is nil and the engines simply don't get this signal.
nonisolated final class AestheticsService: Sendable {
    private let runner = VisionRunner(name: "aesthetics", lanes: 2, timeout: 5)

    var isSupported: Bool {
        if #available(iOS 18.0, *) { return true } else { return false }
    }

    /// nil when unsupported, unavailable, or Vision could not score the image.
    func isUtility(_ image: CGImage) async -> Bool? {
        guard #available(iOS 18.0, *) else { return nil }
        let request = VNCalculateImageAestheticsScoresRequest()
        return await runner.perform([request], on: image) { requests in
            guard let request = requests.first as? VNCalculateImageAestheticsScoresRequest,
                  let observation = request.results?.first else { return nil }
            return observation.isUtility
        }
    }
}
