import Foundation

/// Every tunable number in the similarity pipeline, in one place (ARCHITECTURE §6.1).
/// Feature and blur thresholds are calibrated on a real library (iPhone 15, 7,724 photos,
/// owner-labelled pairs and photos): see DECISIONS.md, D6 amendment of 2026-09-24.
nonisolated struct SimilarityConfig: Sendable {
    /// Photos taken further apart than this are never compared as "similar shots".
    var timeWindow: TimeInterval = 60
    /// Max earlier photos in the window each photo is compared with.
    var maxNeighbours = 8
    /// Feature-print distance (Euclidean, revision 2 prints are unit length, so 0…2)
    /// at or below which two shots count as near-identical.
    var featureThreshold: Float = 0.75
    /// Anchor check: a new member must also be within threshold × slack of the group's
    /// first photo, so chains of "each looks like the next" don't grow forever.
    var anchorSlack: Float = 1.15
    /// dHash Hamming distance for exact / re-saved duplicates anywhere in the library.
    /// The multi-index lookup is exact for values ≤ 3.
    var duplicateHashDistance = 3
    /// dHash distance used inside the time window when no feature print is available
    /// (for example when Vision fails on the simulator).
    var fallbackHashDistance = 10
    /// Groups never grow past this.
    var maxGroupSize = 30
    /// Focus score (edge-to-contrast ratio, see `ImageAnalysis.sharpness`) below which a
    /// photo is suggested as blurry. Fixtures: blurred 0.10–0.14, sharp ≥ 0.25. To be
    /// re-calibrated from owner labels on device (test report F4).
    var blurThreshold: Float = 0.18
    /// Thumbnail edge used for every per-photo computation.
    var thumbnailSide: CGFloat = 256

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
