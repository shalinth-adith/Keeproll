import Foundation

/// Decides whether an image was saved from a messaging app rather than shot on this
/// iPhone. Pure and deterministic; unit-tested in `ProvenanceEngineTests`.
///
/// Signals, all readable on the device without decoding the picture:
/// - **Camera metadata.** Photos captured by the camera carry make, model, lens or
///   exposure tags. Messaging apps strip every one of them. This is the strongest signal,
///   and its presence always clears an image, whatever the other signals say.
/// - **File identity.** WhatsApp and Telegram name their files in recognisable ways and
///   only ever produce JPEGs; the camera writes `IMG_0001.HEIC`.
/// - **Shape.** Chat apps re-encode to fixed long edges (WhatsApp 1600, Telegram 1280,
///   Instagram 1080); camera shots are 12–48 megapixels.
/// - **Location.** Camera shots usually carry GPS; forwards never do.
/// - **Look.** iOS 18's aesthetics model can say the content is a "utility" image.
///
/// The engine is deliberately conservative: favourites are never suggested, an image
/// with camera data is never suggested, and a large image without metadata (probably an
/// export from an editing app) is capped at "possible". Nothing is pre-selected (D9).
nonisolated enum ProvenanceEngine {
    /// Long edges that messaging apps re-encode to. Camera photos never land on these.
    static let chatLongEdges: Set<Int> = [640, 720, 800, 960, 1024, 1080, 1280, 1440, 1600]

    /// Above this long edge an image without metadata is more likely an edited camera
    /// shot than a forward (chat apps cap well below it).
    static let cameraSizedLongEdge = 2400

    static func verdict(for p: AssetProvenance) -> ChatSavedVerdict? {
        if p.isFavorite { return nil }
        if p.hasCameraMetadata == true { return nil }

        var score = 0.0
        var reasons: [ChatSavedVerdict.Reason] = []
        var source = ChatSavedVerdict.Source.unknownApp

        let longEdge = max(p.pixelWidth, p.pixelHeight)
        let (nameSource, nameScore) = classifyFilename(p.originalFilename)
        if nameScore > 0 {
            score += nameScore
            reasons.append(.chatFilename)
            if let nameSource { source = nameSource }
        }
        if p.hasCameraMetadata == false {
            score += 2
            reasons.append(.noCameraData)
        }
        if chatLongEdges.contains(longEdge) {
            score += 1
            reasons.append(.chatDimensions)
            if source == .unknownApp {
                if longEdge == 1600 { source = .whatsapp } else if longEdge == 1280 { source = .telegram }
            }
        }
        if !p.hasLocation {
            score += 0.5
            reasons.append(.noLocation)
        }
        if isJPEG(p.uniformType) {
            score += 0.5
            reasons.append(.jpegOnly)
        }
        if p.isUtility == true {
            score += 1
            reasons.append(.utilityLook)
        }

        // Without a header read, only an explicit chat filename may speak; the shape and
        // JPEG hints are too weak on their own.
        if p.hasCameraMetadata == nil && nameScore < 3 { return nil }
        // No camera data, but camera-sized: probably an export, not a forward.
        let capped = p.hasCameraMetadata == false && longEdge >= cameraSizedLongEdge

        // "Likely" and above need a positive chat sign (name, size or look), not just the
        // absence of camera data: an EXIF-less JPEG could also be a web save or an export.
        let positiveSign = reasons.contains(.chatFilename) || reasons.contains(.chatDimensions) || reasons.contains(.utilityLook)
        let confidence: ChatSavedVerdict.Confidence
        switch score {
        case 4.5... where positiveSign: confidence = capped ? .possible : .veryLikely
        case 3.5... where positiveSign: confidence = capped ? .possible : .likely
        case 2.5...: confidence = .possible
        default: return nil
        }
        return ChatSavedVerdict(confidence: confidence, source: source, reasons: reasons)
    }

    /// (source, score). 3 = an explicit chat-app pattern; 1 = not a camera name; 0 = camera or unknown.
    static func classifyFilename(_ name: String?) -> (ChatSavedVerdict.Source?, Double) {
        guard let name, !name.isEmpty else { return (nil, 0) }
        let base = (name as NSString).deletingPathExtension
        // WhatsApp (Android naming survives when media is forwarded from Android) and iOS WhatsApp
        // camera captures, which use random alphanumerics instead of IMG_.
        if base.range(of: #"^(IMG|VID)-\d{8}-WA\d{4}"#, options: .regularExpression) != nil { return (.whatsapp, 3) }
        if base.range(of: #"^photo_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}"#, options: .regularExpression) != nil { return (.telegram, 3) }
        if base.range(of: #"^(IMG|DSC|DSCF|DSCN|PXL|MVIMG|GOPR|DJI)[_-]?\d{3,}"#, options: [.regularExpression, .caseInsensitive]) != nil { return (nil, 0) }
        if base.range(of: #"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"#, options: [.regularExpression, .caseInsensitive]) != nil { return (nil, 0) } // PhotoKit-generated
        // Random 6–12 character alphanumerics ("UYNZ3K2P"), "image", "photo", "download", "Screenshot" clones.
        if base.range(of: #"^(image|photo|download|received|media)[_\- ]?\d*$"#, options: [.regularExpression, .caseInsensitive]) != nil { return (nil, 1) }
        if base.range(of: #"^[A-Z0-9]{6,12}$"#, options: .regularExpression) != nil { return (nil, 1) }
        return (nil, 0)
    }

    static func isJPEG(_ uti: String?) -> Bool {
        guard let uti = uti?.lowercased() else { return false }
        return uti == "public.jpeg" || uti.hasSuffix(".jpeg") || uti.hasSuffix(".jpg")
    }
}

