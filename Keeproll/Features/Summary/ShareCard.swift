import SwiftUI

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
        .frame(width: 720, height: 720, alignment: .topLeading)
        .background(KeeprollGradient.hero)
    }

    /// Renders at 2× for a crisp 1440 px square.
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
