import Foundation

/// Every tunable number in the similarity pipeline, in one place (ARCHITECTURE §6.1).
/// Starting values; calibrate on a real library and record the result in DECISIONS.md.
nonisolated struct SimilarityConfig: Sendable {
    /// Photos taken further apart than this are never compared as "similar shots".
    var timeWindow: TimeInterval = 60
    /// Max earlier photos in the window each photo is compared with.
    var maxNeighbours = 8
    /// Feature-print distance (Euclidean, revision 2 prints are unit length, so 0…2)
    /// at or below which two shots count as near-identical.
    var featureThreshold: Float = 0.45
    /// Anchor check: a new member must also be within threshold × slack of the group's
    /// first photo, so chains of "each looks like the next" don't grow forever.
    var anchorSlack: Float = 1.35
    /// dHash Hamming distance for exact / re-saved duplicates anywhere in the library.
    /// The multi-index lookup is exact for values ≤ 3.
    var duplicateHashDistance = 3
    /// dHash distance used inside the time window when no feature print is available
    /// (for example when Vision fails on the simulator).
    var fallbackHashDistance = 10
    /// Groups never grow past this.
    var maxGroupSize = 30
    /// Laplacian variance (on a ≤256 px grayscale thumbnail) below which a photo is
    /// suggested as blurry.
    var blurThreshold: Float = 60
    /// Thumbnail edge used for every per-photo computation.
    var thumbnailSide: CGFloat = 256
    /// Assets processed per batch; results stream to the UI after each batch.
    var batchSize = 48

    static let standard = SimilarityConfig()

    /// `standard`, plus any thresholds applied from the DEBUG calibration screen.
    static var current: SimilarityConfig {
        var config = SimilarityConfig.standard
        #if DEBUG
        let defaults = UserDefaults.standard
        if let value = defaults.object(forKey: CalibrationKeys.featureThreshold) as? Double { config.featureThreshold = Float(value) }
        if let value = defaults.object(forKey: CalibrationKeys.blurThreshold) as? Double { config.blurThreshold = Float(value) }
        #endif
        return config
    }
}

nonisolated enum CalibrationKeys {
    static let featureThreshold = "calibration.featureThreshold"
    static let blurThreshold = "calibration.blurThreshold"
}
