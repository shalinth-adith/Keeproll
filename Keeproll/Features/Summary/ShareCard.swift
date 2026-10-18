import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The image behind the Summary "Share" button: the brand mark, the amount freed, and
/// the privacy line. Honest and plain; no app-store badge, no device frame.
struct ShareCard: View {
    let bytesFreed: Int64
    let itemCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 14) {
                KeeprollMarkTile(size: 56)
                Text("Keeproll")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("I freed")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Text(ByteFormatter.string(bytesFreed))
                    .font(.system(size: 92, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("^[\(itemCount) item](inflect: true) reviewed and removed")
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            Label("Nothing left my iPhone.", systemImage: "lock.shield.fill")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.white.opacity(0.16), in: Capsule())
        }
        .padding(44)
        // 750 × 2 = 1500 px: not one of the long edges chat apps re-encode to, so a saved
        // card doesn't look like a forward (QA L5).
        .frame(width: 750, height: 750, alignment: .topLeading)
        .background(KeeprollGradient.hero)
    }

    /// Written into the card's TIFF Software tag. `AssetHeaderReader` recognises it, so a
    /// card saved to Photos is never suggested as "Saved from Chats" (QA L5).
    nonisolated static let softwareTag = "Keeproll share card"

    /// JPEG with the Software tag, written to a temporary file named for the share sheet.
    @MainActor static func file(for image: UIImage) -> URL? {
        guard let cgImage = image.cgImage else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Keeproll.jpg")
        try? FileManager.default.removeItem(at: url)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.92,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFSoftware: softwareTag],
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? url : nil
    }

    /// Renders at 2× for a crisp 1500 px square.
    @MainActor static func image(bytesFreed: Int64, itemCount: Int) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCard(bytesFreed: bytesFreed, itemCount: itemCount))
        renderer.scale = 2
        return renderer.uiImage
    }
}

/// A rendered share card as a transferable image, so `ShareLink` can offer it.
struct ShareCardImage: Transferable {
    let image: UIImage
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in card.image.pngData() ?? Data() }
    }
}
